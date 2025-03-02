const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const RclAllocator = @import("allocator.zig").RclAllocator;
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
    rcl_clock: rcl.rcl_clock_t,

    pub fn init(allocator: RclAllocator, clock_type: ClockType) !Clock {
        var clock: Clock = undefined;
        // pointer to otherwise stack allocator is fine as clock_init calls all copy the underlying object, the pointer is not stored
        // Const cast is also fine as the underlying c calls only use the allocator, they don't modify it. Keeps the zig api cleaner
        const ret = rcl.rcl_clock_init(@intFromEnum(clock_type), &clock.rcl_clock, @constCast(@ptrCast(&allocator.rcl_allocator)));
        if (ret != rcl_error.RCL_RET_OK) return rcl_error.intToRclError(ret);
        return clock;
    }

    pub fn deinit(self: *Clock) void {
        // TODO handle errors?
        _ = rcl.rcl_clock_fini(&self.rcl_clock);
    }
};
