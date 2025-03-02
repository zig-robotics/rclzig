const std = @import("std");
const rcl = @import("rcl.zig").rcl;

const RclAllocator = @import("allocator.zig").RclAllocator;
const Arguments = @import("rclzig.zig").Arguments;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");
const Context = @import("rclzig.zig").Context;

pub const Node = struct {
    rcl_node: rcl.rcl_node_t,

    pub fn init(allocator: RclAllocator, name: [:0]const u8, context: *Context) !Node {
        var return_value: Node = Node{
            // RCL assumes zero init, we can't use zigs "undefined" to initialize or we get already init errors
            .rcl_node = rcl.rcl_get_zero_initialized_node(),
        };
        var node_options = rcl.rcl_node_get_default_options();
        node_options.allocator = allocator.rcl_allocator;
        defer _ = rcl.rcl_node_options_fini(&node_options);

        const rc = rcl.rcl_node_init(&return_value.rcl_node, name, "", @ptrCast(context), &node_options);
        if (rc != rcl_error.RCL_RET_OK) {
            return rcl_error.intToRclError(rc);
        } else {
            return return_value;
        }
    }

    pub fn deinit(self: *Node) void {
        _ = rcl.rcl_node_fini(&self.rcl_node);
    }
};
