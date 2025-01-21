const std = @import("std");
const rcl_allocator_t = @import("rcl.zig").rcl.rcl_allocator_t;

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
        for (new_data[1..]) |*data| {
            data.* = 0;
        }
        new_data[0] = number_of_usize - 1; // Size of the useable data after alloc
        return @ptrCast(&new_data[1]);
    } else |err| switch (err) {
        else => return null,
    }
}

// fn reallocate(ptr: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
fn resize(allocator: *std.mem.Allocator, data_in: ?*anyopaque, number_of_bytes: usize) ?*anyopaque {
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
        // TODO, could this use allocator.dupe? or @memset
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
            // TODO resize in zig won't move the ptr, while malloc(maybe rcl allocator?) says it can deallocate and reallocate
            // That's what should probably happen here?
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

// Set up tp match
// https://github.com/ros2/rcutils/blob/rolling/include/rcutils/allocator.h
pub const Allocator = extern struct {
    // Allocate memory, given a size and the `state` pointer.
    // An error should be indicated by returning `NULL`.
    // void * (*allocate)(size_t size, void * state);
    allocate: *const fn (size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque = &allocate,

    // Deallocate previously allocated memory, mimicking free().
    // Also takes the `state` pointer.
    // void (* deallocate)(void * pointer, void * state);i
    deallocate: *const fn (ptr: ?*anyopaque, state: ?*anyopaque) callconv(.C) void = &deallocate,

    // Reallocate if possible, otherwise it deallocates and allocates.
    //
    // Also takes the `state` pointer.
    //
    // If unsupported then do deallocate and then allocate.
    // This should behave as realloc() does, as opposed to posix's
    // [reallocf](https://linux.die.net/man/3/reallocf), i.e. the memory given
    // by pointer will not be free'd automatically if realloc() fails.
    // For reallocf-like behavior use rcutils_reallocf().
    // This function must be able to take an input pointer of `NULL` and succeed.
    //
    // void * (*reallocate)(void * pointer, size_t size, void * state);
    reallocate: *const fn (ptr: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque = &reallocate,
    // Allocate memory with all elements set to zero, given a number of elements and their size.
    // An error should be indicated by returning `NULL`.
    //void * (*zero_allocate)(size_t number_of_elements, size_t size_of_element, void * state);
    zeroAllocate: *const fn (number_of_elements: usize, size_of_elements: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque = &zeroAllocate,

    // Implementation defined state storage.
    //
    // This is passed as the final parameter to other allocator functions.
    // Note that the contents of the state can be modified even in const-qualified
    // allocator objects.
    // void* state
    zig_allocator: *const std.mem.Allocator,

    pub fn init(self: *Allocator, allocator: *const std.mem.Allocator) void {
        self.allocate = &allocate;
        self.deallocate = &deallocate;
        self.reallocate = &reallocate;
        self.zeroAllocate = &zeroAllocate;
        self.zig_allocator = allocator;
    }

    pub fn init2(allocator: *const std.mem.Allocator) Allocator {
        return Allocator{
            .allocate = &allocate,
            .deallocate = &deallocate,
            .reallocate = &reallocate,
            .zeroAllocate = &zeroAllocate,
            .zig_allocator = allocator,
        };
    }

    pub fn init_rcl(allocator: *const std.mem.Allocator) rcl_allocator_t {
        return rcl_allocator_t{
            .allocate = &allocate,
            .deallocate = &deallocate,
            .reallocate = &reallocate,
            .zero_allocate = &zeroAllocate,
            // TODO is the const cast here really needed? can we take a non const pointer to allocator?
            .state = @constCast(@ptrCast(allocator)),
        };
    }

    pub fn rcl(self: *Allocator) *rcl_allocator_t {
        return @ptrCast(self);
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
    // TODO resize doesn't seem right here
    return resize(allocator, ptr, size);
}

fn zeroAllocate(number_of_elements: usize, size_of_element: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque {
    const allocator: *std.mem.Allocator = @ptrCast(@alignCast(state));
    // TODO, could this use allocator.dupe? or @memset
    return zeroAlloc(allocator, number_of_elements * size_of_element);
}

// pub fn Allocator(comptime zig_allocator: *std.mem.Allocator) type {
//     // return Allocator{ .allocate = &allocate, .deallocate = &deallocate, .reallocate = &reallocate, .zeroAllocate = &zeroAllocate, .zig_allocator = zig_allocator };
//     return extern struct {
//         // Allocate memory, given a size and the `state` pointer.
//         // An error should be indicated by returning `NULL`.
//         // void * (*allocate)(size_t size, void * state);
//         allocate: *const fn (size: usize, state: ?*anyopaque) callconv(.C) ?.anyopaque = &allocate,

//         // Deallocate previously allocated memory, mimicking free().
//         // Also takes the `state` pointer.
//         // void (* deallocate)(void * pointer, void * state);i
//         deallocate: *const fn (ptr: ?*anyopaque, state: ?*anyopaque) callconv(.C) void = &deallocate,

//         // Reallocate if possible, otherwise it deallocates and allocates.
//         //
//         // Also takes the `state` pointer.
//         //
//         // If unsupported then do deallocate and then allocate.
//         // This should behave as realloc() does, as opposed to posix's
//         // [reallocf](https://linux.die.net/man/3/reallocf), i.e. the memory given
//         // by pointer will not be free'd automatically if realloc() fails.
//         // For reallocf-like behavior use rcutils_reallocf().
//         // This function must be able to take an input pointer of `NULL` and succeed.
//         //
//         // void * (*reallocate)(void * pointer, size_t size, void * state);
//         reallocate: *const fn (ptr: ?*anyopaque, size: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque = &reallocate,
//         // Allocate memory with all elements set to zero, given a number of elements and their size.
//         // An error should be indicated by returning `NULL`.
//         //void * (*zero_allocate)(size_t number_of_elements, size_t size_of_element, void * state);
//         zeroAllocate: *const fn (number_of_elements: usize, size_of_elements: usize, state: ?*anyopaque) callconv(.C) ?*anyopaque = &zeroAllocate,

//         // Implementation defined state storage.
//         //
//         // This is passed as the final parameter to other allocator functions.
//         // Note that the contents of the state can be modified even in const-qualified
//         // allocator objects.
//         // void* state
//         zig_allocator: *std.mem.Allocator = zig_allocator,
//     };
// }
