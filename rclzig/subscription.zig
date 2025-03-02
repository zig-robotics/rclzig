const rcl = @import("rcl.zig").rcl;

const std = @import("std");
const rcl_allocator = @import("allocator.zig");
const Node = @import("node.zig").Node;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");

// pub fn SubscriptionCallback(comptime T: type) type {
//     return *const fn (msg: T) anyerror!void;
// }

fn initSub(
    allocator: rcl_allocator.RclAllocator,
    node: *Node,
    comptime MsgT: type,
    topic_name: [:0]const u8,
    qos: rmw.QosProfile,
) !rcl.rcl_subscription_t {
    var subscription = rcl.rcl_get_zero_initialized_subscription();
    var options = rcl.rcl_subscription_get_default_options();
    defer _ = rcl.rcl_subscription_options_fini(&options); // TODO figure out if it is safe to ignore the return code?
    options.qos = qos.rcl().*;
    options.allocator = allocator.rcl_allocator;
    const rc = rcl.rcl_subscription_init(
        &subscription,
        &node.rcl_node,
        @ptrCast(MsgT.getTypeSupportHandle()),
        @ptrCast(topic_name),
        &options,
    );

    if (rc != rcl_error.RCL_RET_OK) {
        return rcl_error.intToRclError(rc);
    }

    return subscription;
}
// The callback should be directly a function
fn SubscriptionCallback(comptime MsgT: type, comptime callback: anytype) type {
    const Signature = enum {
        no_args,
        msg,
        context_msg,
    };
    const CallbackT = @TypeOf(callback);
    const callback_info = switch (@typeInfo(CallbackT)) {
        .Fn => |f| blk: {
            if (f.params.len == 0) break :blk .{ .type = void, .signature = Signature.no_args };
            if (f.params.len == 1) {
                if (f.params[0].type) |MT| if (MT == *const MsgT) {
                    break :blk .{ .type = void, .signature = Signature.msg };
                };
                @compileError("Callback function: " ++ @typeName(CallbackT) ++
                    " has only one arg, but does not match specified message type: " ++
                    @typeName(*const MsgT));
            } else if (f.params.len == 2) {
                if (f.params[1].type) |MT| if (MT == *const MsgT) {
                    if (f.params[0].type) |T| {
                        break :blk .{ .type = T, .signature = Signature.context_msg };
                    }
                    @compileError("Callback function " ++ @typeName(CallbackT) ++
                        " has two args, but the first arg is undefined");
                };
                @compileError("Callback function: " ++ @typeName(CallbackT) ++
                    " has two args, but second arg does not match specified message type: " ++
                    @typeName(*const MsgT));
            }
        },
        else => @compileError("The callback argument must be a function."),
    };

    const signature = callback_info.signature;

    if (signature == .context_msg) {
        return struct {
            const Self = @This();
            pub const ContextT = callback_info.type;
            pub const stateful = true;
            context: ContextT,

            pub fn typeErased(self: *anyopaque, msg: *const anyopaque) void {
                callback(@ptrCast(@alignCast(self)), @ptrCast(@alignCast(msg)));
            }

            pub fn call(self: *Self, msg: *const MsgT) void {
                callback(self.context, msg);
            }
        };
    } else {
        return struct {
            const Self = @This();
            pub const ContextT = callback_info.type;
            pub const stateful = false;

            // TODO decide if we want to allow callbacks to error. if we do, it should probably be a limited set dictated here otherwise the executor has no way to handle them (OOM for example? maybe we don't allow callbacks to allocate?)
            pub fn typeErased(self: *anyopaque, msg: *const anyopaque) void {
                _ = self;
                callback(@ptrCast(@alignCast(msg)));
            }

            pub fn call(msg: *const MsgT) void {
                switch (signature) {
                    .no_args => callback(),
                    .msg => callback(msg),
                    else => unreachable,
                }
            }
        };
    }
}

pub fn Subscription(comptime MsgT: type, comptime callback: anytype) type {
    return struct {
        const Self = @This();
        pub const CallbackT = SubscriptionCallback(MsgT, callback);
        subscription: rcl.rcl_subscription_t,
        msg: MsgT, // TODO this isn't technically needed, but is nice for static implementations. Consider adding a verion that uses a heap pointer?
        callback: if (CallbackT.stateful) CallbackT else void,

        // TODO decide if we want to allow callbacks to error. if we do, it should probably be a limited set dictated here otherwise the executor has no way to handle them (OOM for example? maybe we don't allow callbacks to allocate?)
        pub fn init(
            allocator: rcl_allocator.RclAllocator,
            node: *Node,
            topic_name: [:0]const u8,
            qos: rmw.QosProfile,
        ) !Self {
            // TODO handle partial init
            if (CallbackT.stateful)
                @compileError("Normal init called but callback prodvided requires a context pointer to bind to. Please use initBind instead");
            return Self{
                // RCL assumes zero init, we can't use zigs "undefined" to initialize or we get already init errors
                .subscription = try initSub(allocator, node, MsgT, topic_name, qos),
                // .node = @ptrCast(&node.rcl_node),
                .msg = .{}, // TODO msg should check if it needs init
                .callback = {},
            };
        }

        pub fn initBind(allocator: rcl_allocator.RclAllocator, node: *Node, topic_name: [:0]const u8, qos: rmw.QosProfile, context: CallbackT.ContextT) !Self {
            // TODO handle partial init
            if (!CallbackT.stateful)
                @compileError("Bind init called but callback prodvided is stateless. Please use init instead");
            return Self{
                // RCL assumes zero init, we can't use zigs "undefined" to initialize or we get already init errors
                .subscription = try initSub(allocator, node, MsgT, topic_name, qos),
                .msg = .{},
                .callback = .{ .context = context },
            };
        }

        pub fn deinit(self: *Self, allocator: rcl_allocator.RclAllocator, node: *Node) void {
            if (comptime std.meta.hasMethod(MsgT, "deinit")) {
                self.msg.deinit(allocator);
            }
            // TODO this returns the rcl error, convert it to zig error?
            _ = rcl.rcl_subscription_fini(&self.subscription, @ptrCast(node));
        }
    };
}
