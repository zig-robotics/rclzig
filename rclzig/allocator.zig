const std = @import("std");
const rcl = @import("rcl.zig").rcl;

// Returns the default rcl allocator.
// This will use libc behind the scenes, and is the simplest way to get started.
// Zig wrapped allocators are available below, but be aware that if the RMW does not allow for the
// allocator to be set, you must use the default allocator.
// Due to the nature of the zig wrapper, at least for now, it can't handle independent calls to
// libc that don't go through the wrapper.
pub fn getDefaultRclAllocator() RclAllocator {
    return .{ .rcl_allocator = rcl.rcl_get_default_allocator() };
}

var total_allocations: usize = 0;

fn alloc(allocator: *std.mem.Allocator, number_of_bytes: usize) ?*anyopaque {
    if (number_of_bytes == 0) {
        return null;
    }
    var number_of_usize = number_of_bytes / @sizeOf(usize);
    if (number_of_bytes % @sizeOf(usize) > 0) {
        number_of_usize += 1;
    }

    number_of_usize += 1; // Need room to stuff size
    total_allocations += number_of_usize * @sizeOf(usize);
    std.log.debug("Allocating: {} bytes, total: {}", .{ number_of_usize * @sizeOf(usize), total_allocations });
    if (allocator.alloc(usize, number_of_usize)) |new_data| {
        new_data[0] = number_of_usize - 1; // Size of the useable data after alloc
        return @ptrCast(&new_data[1]);
    } else |err| switch (err) {
        else => return null,
    }
}

fn zeroAlloc(allocator: *std.mem.Allocator, number_of_bytes: usize) ?*anyopaque {
    if (number_of_bytes == 0) {
        return null;
    }
    var number_of_usize = number_of_bytes / @sizeOf(usize);
    if (number_of_bytes % @sizeOf(usize) > 0) {
        number_of_usize += 1;
    }

    number_of_usize += 1; // Need room to stuff size
    total_allocations += number_of_usize * @sizeOf(usize);
    std.log.debug("Zero allocating: {} bytes, total: {}", .{ number_of_usize * @sizeOf(usize), total_allocations });
    if (allocator.alloc(usize, number_of_usize)) |new_data| {
        @memset(new_data[1..], 0);
        new_data[0] = number_of_usize - 1; // Size of the useable data after alloc
        return @ptrCast(&new_data[1]);
    } else |err| switch (err) {
        else => return null,
    }
}

fn realloc(allocator: *std.mem.Allocator, data_in: ?*anyopaque, number_of_bytes: usize) ?*anyopaque {
    if (data_in) |data| {
        if (number_of_bytes == 0) {
            free(allocator, data);
            return null;
        }
        var number_of_usize = number_of_bytes / @sizeOf(usize);
        if (number_of_bytes % @sizeOf(usize) > 0) {
            number_of_usize += 1;
        }

        number_of_usize += 1; // Need room to stuff size

        total_allocations += number_of_usize * @sizeOf(usize);
        const size = @as(*usize, @ptrFromInt(@intFromPtr(data) - @sizeOf(usize))).*;

        var slice = @as([*]usize, @ptrFromInt(@intFromPtr(data) - @sizeOf(usize)))[0 .. size + 1];
        if (allocator.resize(slice, number_of_usize)) {
            slice[0] = number_of_usize - 1; // Size of the useable data after alloc
            if (std.log.logEnabled(std.log.Level.debug, std.log.default_log_scope)) {
                if (number_of_usize > (size + 1)) {
                    total_allocations += number_of_usize - (size + 1);
                    std.log.debug("Resize is adding allocations: {} bytes, total: {}", .{ number_of_usize - (size + 1), total_allocations });
                }
            }
            return @ptrCast(&slice[1]);
        } else {
            return null;
        }
    } else {
        return alloc(allocator, number_of_bytes);
    }
}

fn free(allocator: *std.mem.Allocator, data_in: ?*anyopaque) void {
    if (data_in) |data| {
        const size = @as(*usize, @ptrFromInt(@intFromPtr(data) - @sizeOf(usize))).*;

        const slice = @as([*]usize, @ptrFromInt(@intFromPtr(data) - @sizeOf(usize)))[0 .. size + 1];
        allocator.free(slice);
    }
}

// A wrapper around the underlying rcl allocator type to add a similar zig allocator interface.
// A function accepts this allocator instead of a zig allocator to signal that its the rcl
// thats doing allocations, and not zig native code itself.
// This should be directly castable to an rcl_allocator_t, or the rcl_allocator member can be
// accessed for passing down to rcl.
pub const RclAllocator = extern struct {
    const Error = std.mem.Allocator.Error;
    const Self = @This();
    rcl_allocator: rcl.rcl_allocator_t,

    pub fn alloc(self: *const Self, comptime T: type, n: usize) Error![]T {
        // TODO remove question mark operator?
        return @as([*]T, @ptrCast(self.rcl_allocator.allocate.?(
            @sizeOf(T) * n,
            self.rcl_allocator.state,
        ) orelse return Error.OutOfMemory))[0..n];
    }

    pub fn free(self: *const Self, memory: anytype) void {
        const Slice = @typeInfo(@TypeOf(memory)).Pointer;
        const bytes = std.mem.sliceAsBytes(memory);
        const bytes_len = bytes.len + if (Slice.sentinel != null) @sizeOf(Slice.child) else 0;
        if (bytes_len == 0) return;
        const non_const_ptr = @constCast(bytes.ptr);
        // TODO: https://github.com/ziglang/zig/issues/4298
        @memset(non_const_ptr[0..bytes_len], undefined);
        // TODO remove question mark operator?
        self.rcl_allocator.deallocate.?(@ptrCast(non_const_ptr), self.rcl_allocator.state);
    }

    // TODO for all these functions, the zig versions hande a bunch of alignment stuff too, do we need to handle that here?
    pub fn create(self: *const Self, comptime T: type) Error!*T {
        if (@sizeOf(T) == 0) return @as(*T, @ptrFromInt(std.math.maxInt(usize)));
        // TODO remove question mark operator?
        return @as(*T, @ptrCast(self.rcl_allocator.allocate.?(
            @sizeOf(T),
            self.rcl_allocator.state,
        ) orelse return Error.OutOfMemory));
    }

    pub fn destroy(self: Self, ptr: anytype) void {
        const info = @typeInfo(@TypeOf(ptr)).Pointer;
        if (info.size != .One) @compileError("ptr must be a single item pointer");
        const T = info.child;
        if (@sizeOf(T) == 0) return;
        const non_const_ptr = @as([*]u8, @ptrCast(@constCast(ptr)));
        // TODO remove question mark operator?
        self.rcl_allocator.deallocate.?(non_const_ptr, self.rcl_allocator.state);
    }

    pub fn realloc(self: Self, old_mem: anytype, new_n: usize) t: {
        const Slice = @typeInfo(@TypeOf(old_mem)).Pointer;
        break :t Error![]align(Slice.alignment) Slice.child;
    } {
        const Slice = @typeInfo(@TypeOf(old_mem)).Pointer;
        const T = Slice.child;
        const bytes = std.mem.sliceAsBytes(old_mem);
        const non_const_ptr = @constCast(bytes.ptr);
        // TODO remove question mark operator?
        return @as([*]u8, @ptrCast(self.rcl_allocator.reallocate.?(
            @ptrCast(non_const_ptr),
            @sizeOf(T) * new_n,
            self.rcl_allocator.state,
        ) orelse return Error.OutOfMemory))[0..new_n];
    }

    // Create an rcl allocator from a backing zig allocator.
    // this has a lot of pointy edges, namely the rmw at this time will do what it wants.
    // data coming back from the rmw (dynamic types in subscriberes etc) will most often be raw
    // malloc as the rmw implementations do not have access to the rcl / rmw allocator types.
    // since this implementation stuffs size as a header, even with a malloc based zig allocator
    // it is incompatible with memory that has been created or manipulated outside of this wrapper.
    // its also worth noting that even though the rmw *does* have the notion of custom allocators,
    // it is hard coded to use the default allocator https://github.com/ros2/rmw/blob/jazzy/rmw/src/allocators.c
    // Really this should only be used in tests, or portions of rcl you're sure respect the passed
    // allocator (this seems to be most of rcl, only the boundaries to the rmw are rough but use at
    // your own risk)
    pub fn initFromZig(allocator: *std.mem.Allocator) Self {
        return .{
            .rcl_allocator = .{
                .allocate = &allocate,
                .deallocate = &deallocate,
                .reallocate = &reallocate,
                .zero_allocate = &zeroAllocate,
                .state = @ptrCast(allocator),
            },
        };
    }
};

// These functions match the definitions for the rcutils allocator
// https://github.com/ros2/rcutils/blob/rolling/include/rcutils/allocator.h
fn allocate(size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(state));
    return alloc(allocator, size);
}

fn deallocate(ptr: ?*anyopaque, state: ?*anyopaque) callconv(.C) void {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(state));
    free(allocator, ptr);
}

fn reallocate(ptr: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(state));
    return realloc(allocator, ptr, size);
}

fn zeroAllocate(number_of_elements: usize, size_of_element: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(state));
    // TODO, could this use allocator.dupe? or @memset
    return zeroAlloc(allocator, number_of_elements * size_of_element);
}
