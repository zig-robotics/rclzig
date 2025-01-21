const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const rcl_error = @import("error.zig");
const rmw = @import("rmw.zig");
const rcl_allocator = @import("allocator.zig");
const Context = @import("rclzig.zig").Context;
const time = @import("time.zig");

pub const TimerCallback = *const fn () void;
pub const TimerCallbackWithError = *const fn () anyerror!void;

pub const TimerCallbacks = union(enum) {
    callback: TimerCallback,
    callback_with_error: TimerCallbackWithError,
};

pub const TimerError = error{
    InvalidTimerCallbackType,
};

pub const Timer = struct {
    rcl_timer: rcl.rcl_timer_t,
    callback: TimerCallbacks,

    // TODO switch to duration type?
    // TODO I think this style of init doesn't work because rcl_timer itself is a member, not a pointer,
    // so the copy on return throws. things off??
    // I'm not convinced since its only members are pointers?
    // DOC
    // Allocator is a pointer here because the underlying rcl allocator tracks "state" as a pointer
    // TODO make a ziggy callback type?
    pub fn init(allocator: *std.mem.Allocator, callback: TimerCallbacks, clock: *time.Clock, context: *Context, period_ns: i64) !Timer {
        var return_value = Timer{
            .rcl_timer = rcl.rcl_get_zero_initialized_timer(),
            .callback = callback,
        };
        // TODO this here is a good lesson
        // This line here is why we can't do the nice "constructor" init. We're storing a pointer to a temporary
        // since the rclzig allocator needs to be only pointers
        // TODO trying to work around this by taking a pointer to the allocator
        // return_value.rclzig_allocator.zig_allocator = &return_value.allocator;
        const rc = rcl.rcl_timer_init(
            &return_value.rcl_timer,
            &clock.rcl_clock,
            context,
            period_ns,
            null,
            rcl_allocator.Allocator.init_rcl(allocator),
        );
        if (rc != rcl_error.RCL_RET_OK) {
            return rcl_error.intToRclError(rc);
        }
        return return_value;
    }

    pub fn deinit(self: *Timer) void {
        // TODO handle return code?
        _ = rcl.rcl_timer_fini(&self.rcl_timer);
    }
};
