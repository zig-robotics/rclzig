const rcl = @import("rcl.zig").rcl;

const std = @import("std");
const RclAllocator = @import("allocator.zig").RclAllocator;
const Node = @import("node.zig").Node;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");

pub fn Publisher(comptime T: type) type {
    return struct {
        const Self = @This();
        publisher: rcl.rcl_publisher_t,

        pub fn init(allocator: RclAllocator, node: *Node, topic: [:0]const u8, qos: rmw.QosProfile) !Self {
            var return_value = Self{
                // RCL assumes zero init, we can't use zigs "undefined" to initialize or we get already init errors
                .publisher = rcl.rcl_get_zero_initialized_publisher(),
            };
            var options = rcl.rcl_publisher_get_default_options();
            options.qos = qos.rcl().*;
            options.allocator = allocator.rcl_allocator;

            const rc = rcl.rcl_publisher_init(
                &return_value.publisher,
                @ptrCast(&node.rcl_node),
                @ptrCast(T.getTypeSupportHandle()),
                topic,
                &options,
            );
            if (rc != rcl_error.RCL_RET_OK) {
                return (rcl_error.intToRclError(rc));
            }
            return return_value;
        }

        pub fn publish(self: *Self, msg: *const T) !void {
            // const rc = rcl.rcl_publish(&self.publisher, @as(?*const anyopaque, @ptrCast(msg)), null);
            const rc = rcl.rcl_publish(&self.publisher, @ptrCast(msg), null);
            if (rc != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(rc);
            }
        }

        pub fn deinit(self: *Self, node: *Node) !void {
            // TODO defer can't handle errors, should this not return one?
            const rc = rcl.rcl_publisher_fini(&self.publisher, @ptrCast(&node.rcl_node));
            if (rc != rcl_error.RCL_RET_OK) {
                return rcl_error.intToRclError(rc);
            }
        }
    };
}
