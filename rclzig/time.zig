const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const rcl_allocator = @import("allocator.zig");
const rcl_error = @import("error.zig");

pub const ClockType = enum(rcl.rcl_clock_type_t) {
    uninitialized = rcl.RCL_CLOCK_UNINITIALIZED,
    ros_time = rcl.RCL_ROS_TIME,
    system_time = rcl.RCL_SYSTEM_TIME,
    steady_time = rcl.RCL_STEADY_TIME,
};

pub const TimePointValue = rcl.rcutils_time_point_value_t;
pub const DurationValue = rcl.rcl_duration_value_t; // This covers rcl_duration_value, and rcutils_duration_value (mayble also rmw?)

pub const Duration = rcl.rcl_duration_t;

pub const ClockChange = enum(rcl.rcl_clock_change_t) {
    ros_time_no_change = rcl.RCL_ROS_TIME_NO_CHANGE,
    ros_time_activated = rcl.RCL_ROS_TIME_ACTIVATED,
    ros_time_deactivated = rcl.RCL_ROS_TIME_DEACTIVATED,
    system_time_no_change = rcl.RCL_SYSTEM_TIME_NO_CHANGE,
};

pub const Clock = struct {
    rcl_clock: rcl.rcl_clock_t = undefined,

    pub fn init(allocator: *const std.mem.Allocator, clock_type: ClockType) !Clock {
        var clock = Clock{};
        _ = rcl.rcl_clock_init(@intFromEnum(clock_type), &clock.rcl_clock, @constCast(&rcl_allocator.Allocator.init_rcl(allocator)));
        defer _ = rcl.rcl_clock_fini(@ptrCast(&clock));
        return clock;
    }

    pub fn deinit(self: *Clock) void {
        // TODO handle errors?
        _ = rcl.rcl_clock_fini(&self.rcl_clock);
    }
};
