const std = @import("std");

// TODO move to an rclzig traits thing?
pub fn hasDeinitWithAllocator(comptime T: type) bool {
    comptime {
        if (std.meta.hasFn(T, "deinit")) {
            if (@typeInfo(T).Fn.args.len == 1 and @typeInfo(T.Fn.args[0].arg_type.?) == std.mem.Allocator) {
                return true;
            }
        }
        return false;
    }
}

// TODO move to an rclzig traits thing?
pub fn hasInitWithAllocator(comptime T: type) bool {
    comptime {
        if (std.meta.hasFn(T, "init")) {
            if (@typeInfo(T).Fn.args.len == 1 and @typeInfo(T.Fn.args[0].arg_type.?) == std.mem.Allocator) {
                return true;
            }
        }
        return false;
    }
}
