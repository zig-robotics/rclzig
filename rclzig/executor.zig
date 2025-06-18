const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const Subscription = @import("subscription.zig").Subscription;
// const SubscriptionCallback = @import("subscription.zig").Callback;
const Timer = @import("timer.zig").Timer;
const Context = @import("rclzig.zig").Context;
const RclAllocator = @import("allocator.zig").RclAllocator;
const rcl_error = @import("rclzig.zig").rcl_error;

const TypeErasedSubscriptionCallback = *const fn (sub: *anyopaque, msg: *const anyopaque) void;

// TODO all these closures encur a runtime indirection with the callback pointer
// This isn't needed in most cases since callbacks are all known at compile time
// Create a static executor that can somehow remove this indirection?
const SubscriptionClosure = struct {
    rcl_subscription: *rcl.rcl_subscription_t,
    context: *anyopaque,
    msg: *anyopaque,
    callback: TypeErasedSubscriptionCallback,

    pub fn init(sub: anytype) SubscriptionClosure {
        const stateful = @TypeOf(sub.*).CallbackT.stateful;
        return SubscriptionClosure{
            .context = if (stateful) sub.callback.context else undefined,
            .rcl_subscription = &sub.subscription,
            .msg = &sub.msg,
            .callback = &@TypeOf(sub.*).CallbackT.typeErased,
        };
    }
};

const TypeErasedServiceCallback = *const fn (service: *anyopaque, req: *const anyopaque, resp: *anyopaque) void;

const ServiceClosure = struct {
    rcl_service: *rcl.rcl_service_t,
    context: *anyopaque,
    request: *anyopaque,
    response: *anyopaque,
    callback: TypeErasedServiceCallback,

    pub fn init(service: anytype) ServiceClosure {
        return ServiceClosure{
            .context = service.callback.context,
            .rcl_service = &service.service,
            .request = &service.request,
            .response = &service.response,
            .callback = &@TypeOf(service.*).CallbackT.typeErased,
        };
    }
};

const TypeErasedClientCallback = *const fn (client: *anyopaque, resp: *const anyopaque) void;

const ClientClosure = struct {
    rcl_client: *rcl.rcl_client_t,
    context: *anyopaque,
    response: *anyopaque,
    callback: TypeErasedClientCallback,

    pub fn init(client: anytype) ClientClosure {
        return ClientClosure{
            .context = client.callback.context,
            .rcl_client = &client.client,
            .response = &client.response,
            .callback = &@TypeOf(client.*).CallbackT.typeErased,
        };
    }
};

const TimerClosure = struct {
    rcl_timer: *rcl.rcl_timer_t,
    circumstance: *anyopaque,
    callback: *const fn (circumstance: *anyopaque) void,

    pub fn init(timer: anytype) TimerClosure {
        const stateful = @TypeOf(timer.*).stateful;
        return .{
            .rcl_timer = &timer.rcl_timer,
            .circumstance = if (stateful) timer.circumstance else undefined, // TODO circumstance should be optional and error if called incorrectly?
            .callback = &@TypeOf(timer.*).typeErrased,
        };
    }
};

// A very basic executor supporting timers and subscriptions
pub const Executor = struct {
    // make a static version?
    // TODO unamaged arraylist would be better
    subscriptions: std.ArrayList(SubscriptionClosure),
    services: std.ArrayList(ServiceClosure),
    clients: std.ArrayList(ClientClosure),
    timers: std.ArrayList(TimerClosure),

    pub fn init(allocator: std.mem.Allocator) !Executor {
        const to_return = Executor{
            .subscriptions = .init(allocator),
            .services = .init(allocator),
            .clients = .init(allocator),
            .timers = .init(allocator),
        };

        return to_return;
    }
    pub fn deinit(self: *Executor) void {
        self.subscriptions.deinit();
        self.services.deinit();
        self.clients.deinit();
        self.timers.deinit();
    }

    pub fn addSubscription(self: *Executor, sub: anytype) !void {
        try self.subscriptions.append(SubscriptionClosure.init(sub));
    }
    pub fn addTimer(self: *Executor, timer: anytype) !void {
        try self.timers.append(TimerClosure.init(timer));
    }

    pub fn addService(self: *Executor, service: anytype) !void {
        try self.services.append(ServiceClosure.init(service));
    }

    pub fn addClient(self: *Executor, client: anytype) !void {
        try self.clients.append(ClientClosure.init(client));
    }

    // TODO does this need to be the rcl allocator or can it be the zig allocator?
    pub fn spin(self: Executor, allocator: RclAllocator, context: *Context) !void {
        const start_time = std.time.timestamp();
        const spin_time: i64 = 10; // TODO make this spin forever, this is here for test purposes only
        while ((std.time.timestamp() - start_time) < spin_time) {
            // TODO this will recreate the wait set every time it loops which is wasteful
            // Figure out if there's some way we want to streamline updtes to the waitset, or simply enforce this to be a static executor
            // TODO check rcl ok as well?
            try self.spinOnce(allocator, context, @max(spin_time - (std.time.timestamp() - start_time), 0));
        }
    }

    // TODO does this need to be the rcl allocator or can it be the zig allocator?
    pub fn spinOnce(self: Executor, allocator: RclAllocator, context: *Context, timeout_ms: isize) !void {
        var wait_set = rcl.rcl_get_zero_initialized_wait_set();
        // TODO error handling
        _ = rcl.rcl_wait_set_init(
            &wait_set,
            self.subscriptions.items.len,
            0,
            self.timers.items.len,
            self.clients.items.len,
            self.services.items.len,
            0,
            context,
            allocator.rcl_allocator,
        );
        defer _ = rcl.rcl_wait_set_fini(&wait_set);

        // TODO error handling?
        _ = rcl.rcl_wait_set_clear(&wait_set);
        for (self.subscriptions.items) |sub| {
            // TODO error handling?
            _ = rcl.rcl_wait_set_add_subscription(&wait_set, sub.rcl_subscription, null);
        }
        for (self.clients.items) |client| {
            // TODO error handling?
            _ = rcl.rcl_wait_set_add_client(&wait_set, client.rcl_client, null);
        }
        for (self.services.items) |service| {
            // TODO error handling?
            _ = rcl.rcl_wait_set_add_service(&wait_set, service.rcl_service, null);
        }
        for (self.timers.items) |timer| {
            // TODO error handling?
            _ = rcl.rcl_wait_set_add_timer(&wait_set, timer.rcl_timer, null);
        }

        var ret = rcl.rcl_wait(&wait_set, std.time.ns_per_ms * timeout_ms);
        if (ret == rcl.RCL_RET_TIMEOUT) {
            // TODO should this return error?
            return;
        }

        for (0..wait_set.size_of_timers) |i| if (wait_set.timers[i]) |_| {
            const asdf = rcl.rcl_timer_call(self.timers.items[i].rcl_timer);
            if (asdf == rcl_error.RCL_RET_TIMER_CANCELED) {
                continue;
            }
            if (asdf != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(asdf);
            }
            self.timers.items[i].callback(self.timers.items[i].circumstance);
        };

        for (0..wait_set.size_of_subscriptions) |i| if (wait_set.subscriptions[i]) |rcl_subscription| {
            // The subscription is ready...
            var message_info: rcl.rmw_message_info_t = undefined;
            // TODO rcl_take can fill out the provided msg as null pretty sure, we need to capture this
            const value = rcl.rcl_take(rcl_subscription, self.subscriptions.items[i].msg, &message_info, null);
            if (value != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(value);
            }

            // This is where the flip from rcl to zig language occurs
            self.subscriptions.items[i].callback(
                self.subscriptions.items[i].context,
                self.subscriptions.items[i].msg,
            );
        };

        for (0..wait_set.size_of_clients) |i| if (wait_set.clients[i]) |rcl_client| {
            // The client is ready...
            var info: rcl.rmw_service_info_t = undefined;
            // TODO rcl_take can fill out the provided msg as null pretty sure, we need to capture this
            const value = rcl.rcl_take_response_with_info(rcl_client, &info, self.clients.items[i].response);
            if (value != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(value);
            }

            // This is where the flip from rcl to zig language occurs
            self.clients.items[i].callback(
                self.clients.items[i].context,
                self.clients.items[i].response,
            );
        };

        for (0..wait_set.size_of_services) |i| if (wait_set.services[i]) |rcl_service| {
            // The client is ready...
            var info: rcl.rmw_service_info_t = undefined;
            // TODO rcl_take can fill out the provided msg as null pretty sure, we need to capture this
            const value = rcl.rcl_take_request_with_info(rcl_service, &info, self.services.items[i].request);
            if (value != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(value);
            }

            // This is where the flip from rcl to zig language occurs
            self.services.items[i].callback(
                self.services.items[i].context,
                self.services.items[i].request,
                self.services.items[i].response,
            );

            ret = rcl.rcl_send_response(rcl_service, &info.request_id, self.services.items[i].response);
            if (ret != rcl_error.RCL_RET_OK) return rcl_error.intToRclError(ret);
        };
    }
};
