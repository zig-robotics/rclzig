const std = @import("std");
const rcl = @import("rcl.zig").rcl;
const rcl_error = @import("error.zig");
const rmw = @import("rmw.zig");
const RclAllocator = @import("allocator.zig").RclAllocator;
const Context = @import("rclzig.zig").Context;
const time = @import("time.zig");

pub fn Timer(callback: anytype) type {
    const CallbackT = @TypeOf(callback);
    const CircumstanceT = switch (@typeInfo(CallbackT)) {
        .Fn => |f| if (f.params.len == 0)
            void
        else if (f.params.len == 1)
            if (f.params[0].type) |T|
                T
            else
                @compileError("Callback function " ++ @typeName(CallbackT) ++
                    " an argument, but the type is undefined")
        else
            @compileError("Callback has too many arguments. Callbacks can either be stateless and take no arguments or be stateful and take a single context argument."),
        else => @compileError("Callback must be a function."),
    };

    if (CircumstanceT != void) {
        return struct {
            const Self = @This();
            pub const stateful = true;
            rcl_timer: rcl.rcl_timer_t,
            circumstance: CircumstanceT, // TODO context is taken, pick a better alternative namde?

            pub fn init(
                allocator: RclAllocator,
                clock: *time.Clock,
                context: *Context,
                period_ns: i64,
                circumstance: CircumstanceT,
            ) !Self {
                return .{
                    .rcl_timer = try initTimer(allocator, clock, context, period_ns),
                    .circumstance = circumstance,
                };
            }

            pub fn typeErrased(circumstance: *anyopaque) void {
                callback(@ptrCast(@alignCast(circumstance)));
            }

            pub fn deinit(self: *Self) void {
                // TODO handle return code?
                // Or link to where its safe to ignore
                _ = rcl.rcl_timer_fini(&self.rcl_timer);
            }
        };
    } else {
        return struct {
            const Self = @This();
            pub const stateful = false;
            rcl_timer: rcl.rcl_timer_t,

            pub fn init(
                allocator: RclAllocator,
                clock: *time.Clock,
                context: *Context,
                period_ns: i64,
            ) !Self {
                return .{
                    .rcl_time = try initTimer(allocator, clock, context, period_ns),
                };
            }

            pub fn typeErrased(circumstance: *anyopaque) void {
                _ = circumstance;
                callback();
            }

            pub fn deinit(self: *Self) void {
                // TODO handle return code?
                _ = rcl.rcl_timer_fini(&self.rcl_timer);
            }
        };
    }
}

fn initTimer(allocator: RclAllocator, clock: *time.Clock, context: *Context, period_ns: i64) !rcl.rcl_timer_t {
    var rcl_timer = rcl.rcl_get_zero_initialized_timer();

    const rc = rcl.rcl_timer_init(
        &rcl_timer,
        &clock.rcl_clock,
        context,
        period_ns,
        null,
        allocator.rcl_allocator,
    );
    if (rc != rcl_error.RCL_RET_OK) {
        return rcl_error.intToRclError(rc);
    }
    return rcl_timer;
}
