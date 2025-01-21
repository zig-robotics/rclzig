const rcl = @import("rcl.zig").rcl;

const std = @import("std");
const rcl_allocator = @import("allocator.zig");
const trait = @import("trait.zig");
const Node = @import("node.zig").Node;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");

pub fn SubscriptionCallback(comptime T: type) type {
    return *const fn (msg: T) anyerror!void;
}

pub fn Subscription(comptime T: type) type {
    return struct {
        const Self = @This();
        subscription: rcl.rcl_subscription_t,
        msg: T, // TODO I'm not convinced this needs to be here UPDATE this does need to be here, or at least we need a place for the RMW to write to
        node: *rcl.rcl_node_t,
        callback: SubscriptionCallback(T),
        pub fn typeErasedCallback(self: *anyopaque, msg_in: *const anyopaque) anyerror!void {
            var sub: *Self = @ptrCast(@alignCast(self));
            const msg: *const T = @ptrCast(@alignCast(msg_in));
            try sub.callback(msg.*);
        }

        // TODO this should accept allocator not by pointer to be more ziggy? This is a bit tough to make work with the rcl allocator
        pub fn init(allocator: *const std.mem.Allocator, node: *Node, callback: SubscriptionCallback(T), topic_name: [:0]const u8, qos: rmw.QosProfile) !Self {
            // TODO handle partial init
            var new_sub = Self{
                // RCL assumes zero init, we can't use zigs "undefined" to initialize or we get already init errors
                .subscription = rcl.rcl_get_zero_initialized_subscription(),
                .node = @ptrCast(&node.rcl_node),
                .msg = .{},
                .callback = callback,
            };

            var options = rcl.rcl_subscription_get_default_options();
            defer _ = rcl.rcl_subscription_options_fini(&options);
            options.qos = qos.rcl().*;
            options.allocator = rcl_allocator.Allocator.init_rcl(allocator);
            const rc = rcl.rcl_subscription_init(
                &new_sub.subscription,
                new_sub.node,
                @ptrCast(T.getTypeSupportHandle()), // TODO consider moving type support back to converted rcl? (requires msg generation change)
                @ptrCast(topic_name),
                &options,
            );

            if (rc != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(rc);
            }

            return new_sub;
        }

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            // TODO this fini requires node, this means fini order is important? this must fini before node?
            if (comptime trait.hasDeinitWithAllocator(T)) {
                self.msg.deinit(allocator); // TODO this seems to double free? TODO check if this has been initted?
            }
            // TODO this returns the rcl error, convert it to zig error?
            _ = rcl.rcl_subscription_fini(&self.subscription, @ptrCast(self.node));
        }
    };
}
