const std = @import("std");

// This is pub mainly for tests, please use sparingly. Favor rclzig interfaces instead
pub const rcl = @import("rcl.zig").rcl;

pub const allocator = @import("allocator.zig");
pub const RclAllocator = @import("allocator.zig").RclAllocator;

pub const node = @import("node.zig");
pub const Node = node.Node;

pub const subscription = @import("subscription.zig");
pub const publisher = @import("publisher.zig");
pub const rosidl_runtime = @import("rosidl_runtime.zig");
pub const rmw = @import("rmw.zig");

pub const service = @import("service.zig");
pub const client = @import("client.zig");

// Sequence
pub const Sequence = @import("sequence.zig").Sequence;
pub const SequenceError = @import("sequence.zig").SequenceError;

// RosString used in messages
pub const RosString = @import("string.zig").RosString;

// Timer
// pub const timer = @import("timer.zig");
pub const Timer = @import("timer.zig").Timer;

pub const time = @import("time.zig");

// const ArgumentsImpl = opaque {};
// pub const Arguments = extern struct {
//     impl: ?*ArgumentsImpl = null,
// };
pub const Arguments = rcl.rcl_arguments_t;

// TODO remove this? we should really only expose the error sets
pub const rcl_error = @import("error.zig");

// const ContextImpl = opaque {};
// pub const Context = extern struct {
//     global_arguments: Arguments = Arguments{},
//     impl: ?*ContextImpl = null,
//     instance_id_storage: [8]u8 align(8) = @import("std").mem.zeroes([8]u8),
// };
pub const Context = rcl.rcl_context_t;

pub const Executor = @import("executor.zig").Executor;

pub fn init(allocator_: RclAllocator) !Context {
    var init_options: rcl.rcl_init_options_t = rcl.rcl_get_zero_initialized_init_options();
    var rc = rcl.rcl_init_options_init(&init_options, allocator_.rcl_allocator);
    if (rc != rcl_error.RCL_RET_OK) {
        return (rcl_error.intToRclError(rc));
    }
    defer {
        // Should be safe to ignore return
        // https://github.com/ros2/rcl/blob/rolling/rcl/include/rcl/init_options.h#L130
        _ = rcl.rcl_init_options_fini(@ptrCast(&init_options));
    }
    var context: Context = rcl.rcl_get_zero_initialized_context();

    // TODO handle command line arguments???
    rc = rcl.rcl_init(0, null, &init_options, @ptrCast(&context));
    if (rc != rcl_error.RCL_RET_OK) {
        return (rcl_error.intToRclError(rc));
    }
    return context;
}

pub fn shutdown(context: *Context) void {
    // Should be safe to ingore return
    // https://github.com/ros2/rcl/blob/rolling/rcl/include/rcl/init.h#L107
    _ = rcl.rcl_shutdown(context);
    // Should be safe to ignore return
    // https://github.com/ros2/rcl/blob/rolling/rcl/include/rcl/context.h#L185
    _ = rcl.rcl_context_fini(context);
}
