const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const Subscription = @import("subscription.zig").Subscription;
// const SubscriptionCallback = @import("subscription.zig").Callback;
const Timer = @import("timer.zig").Timer;
const Context = @import("rclzig.zig").Context;
const RclAllocator = @import("allocator.zig").RclAllocator;
const rcl_error = @import("rclzig.zig").rcl_error;

const TypeErasedSubscriptionCallback = *const fn (sub: *anyopaque, msg: *const anyopaque) void;

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

const TimerClosure = struct {
    rcl_timer: *rcl.rcl_timer_t,
    circumstance: *anyopaque,
    callback: *const fn (circumstance: *anyopaque) void,

    pub fn init(timer: anytype) TimerClosure {
        const stateful = @TypeOf(timer.*).stateful;
        return .{
            .rcl_timer = &timer.rcl_timer,
            .circumstance = if (stateful) timer.circumstance else undefined,
            .callback = &@TypeOf(timer.*).typeErrased,
        };
    }
};

// A very basic executor supporting timers and subscriptions
pub const Executor = struct {
    // make a static version?
    subscriptions: std.ArrayList(SubscriptionClosure),
    timers: std.ArrayList(TimerClosure),

    pub fn init(allocator: std.mem.Allocator) !Executor {
        const to_return = Executor{
            .subscriptions = std.ArrayList(SubscriptionClosure).init(allocator),
            .timers = std.ArrayList(TimerClosure).init(allocator),
        };

        return to_return;
    }
    pub fn deinit(self: *Executor) void {
        self.subscriptions.deinit();
        self.timers.deinit();
    }

    pub fn addSubscription(self: *Executor, sub: anytype) !void {
        try self.subscriptions.append(SubscriptionClosure.init(sub));
    }
    pub fn addTimer(self: *Executor, timer: anytype) !void {
        try self.timers.append(TimerClosure.init(timer));
    }
    // TODO does this need to be the rcl allocator or can it be the zig allocator?
    pub fn spin(self: Executor, allocator: RclAllocator, context: *Context) !void {
        var wait_set = rcl.rcl_get_zero_initialized_wait_set();
        // TODO error handling
        _ = rcl.rcl_wait_set_init(&wait_set, self.subscriptions.items.len, 0, self.timers.items.len, 0, 0, 0, context, allocator.rcl_allocator);
        defer _ = rcl.rcl_wait_set_fini(&wait_set);

        const start_time = std.time.timestamp();
        while ((std.time.timestamp() - start_time) < 10) {
            // _ = rclc.rclc_executor_spin_some(&executor, 10 * std.time.us_per_s);
            // TODO error handling?
            _ = rcl.rcl_wait_set_clear(&wait_set);
            for (self.subscriptions.items) |sub| {
                _ = rcl.rcl_wait_set_add_subscription(&wait_set, sub.rcl_subscription, null);
            }
            for (self.timers.items) |timer| {
                _ = rcl.rcl_wait_set_add_timer(&wait_set, timer.rcl_timer, null);
            }

            const ret = rcl.rcl_wait(&wait_set, std.time.ns_per_ms * 100);
            if (ret == rcl.RCL_RET_TIMEOUT) {
                continue;
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
        }
    }
};
