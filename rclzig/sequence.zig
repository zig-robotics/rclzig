const std = @import("std");

const SequenceError = error{
    AtUpperBound,
};

pub fn Sequence(comptime T: type, comptime upper_bound: ?usize) type {
    return extern struct {
        const Self = @This();
        data: [*]T,
        size: usize,
        capacity: usize,

        pub const empty = Self{
            .data = undefined,
            .size = 0,
            .capacity = 0,
        };

        pub fn deinit(self: *Self, allocator: anytype) void {
            if (comptime std.meta.hasMethod(T, "deinit"))
                for (self.data[0..self.size]) |*item| item.deinit(allocator);

            if (self.capacity > 0) {
                allocator.free(self.data[0..self.capacity]);
            }
            self.* = .empty;
        }

        // The sequence assumes ownership of any owned memory
        pub fn append(self: *Self, allocator: anytype, new_value: T) !void {
            (try self.addOneNoInit(allocator)).* = new_value;
        }

        fn addOneNoInit(self: *Self, allocator: anytype) !*T {
            var new_data: *T = undefined;
            if (self.size < self.capacity) {
                new_data = &self.data[self.size];
                self.size += 1;
            } else {
                if (upper_bound) |bound| {
                    if (self.capacity == bound) {
                        return SequenceError.AtUpperBound;
                    }
                }

                // In this case we should be at the limit of capacity, and not over
                std.debug.assert(self.size == self.capacity);

                // TODO bound arrays should init the expected size? does it make sense to be able to reach this if bounded?
                const new_alloc = if (self.capacity == 0)
                    try allocator.alloc(T, 1)
                else
                    try allocator.realloc(self.data[0..self.capacity], self.capacity + 1);
                self.capacity = new_alloc.len;
                self.size = self.capacity;
                self.data = new_alloc.ptr;
                new_data = &new_alloc[new_alloc.len - 1];
            }
            return new_data;
        }

        pub fn addOne(self: *Self, allocator: anytype) !*T {
            const new_data = try self.addOneNoInit(allocator);
            if (comptime std.meta.hasFn(T, "init")) {
                new_data.* = try T.init(allocator);
            }
            return new_data;
        }

        pub fn reserve(self: *Self, allocator: anytype, size: usize) !void {
            if (self.capacity == 0) {
                self.data = (try allocator.alloc(T, size)).ptr;
                self.capacity = size;
            } else if (size > self.capacity) {
                self.data = (try allocator.realloc(self.data[0..self.capacity], size)).ptr;
                self.capacity = size;
            }
        }

        pub fn asSlice(self: *const Self) []T {
            std.debug.assert(self.size <= self.capacity);
            return self.data[0..self.size];
        }

        // TODO add more array list style functions directly?
        // For now it is suggested to use something from the std lib like array list paired with
        // a from owned call.

        // The Sequene assumes ownership of the passed slice.
        // Following calls must use the same allocator that the original slice was created with.
        // Size of pointer must respect upper bound if this is a bound sequence.
        pub fn fromOwnedSlice(owned: []T) RT: {
            if (upper_bound != null)
                break :RT SequenceError!Self
            else
                break :RT Self;
        } {
            if (upper_bound) |bound| if (bound < owned.len) return SequenceError.AtUpperBound;

            return .{
                .data = owned.ptr,
                .size = owned.len,
                .capacity = owned.len,
            };
        }

        // Returns the sequence as an array list. The returned array list owns the memory.
        // This clears the internal values so they can't be accidentally used again.
        pub fn toArrayList(self: *Self) std.ArrayListUnmanaged(T) {
            defer {
                self.* = .empty;
            }
            return .{
                .items = self.asSlice(),
                .capacity = self.capacity,
            };
        }

        // Assumes ownership and clears the passed array list
        pub fn fromArrayList(list: *std.ArrayListUnmanaged(T)) Self {
            defer {
                list.* = .empty;
            }
            return .{
                .data = list.items.ptr,
                .size = list.items.len,
                .capacity = list.capacity,
            };
        }
    };
}

test "Test sequence zig allocator" {
    const allocator = std.testing.allocator;

    var sequence = Sequence(u8, null).empty;
    errdefer sequence.deinit(allocator);
    // empty deinit should be safe
    sequence.deinit(allocator);

    try sequence.append(allocator, 1);
    try sequence.append(allocator, 2);
    try sequence.append(allocator, 3);
    try sequence.append(allocator, 4);
    try std.testing.expectEqualSlices(u8, sequence.asSlice(), &.{ 1, 2, 3, 4 });

    sequence.deinit(allocator);

    var array_list = std.ArrayListUnmanaged(u8).empty;
    try array_list.append(allocator, 4);
    try array_list.append(allocator, 3);
    try array_list.append(allocator, 2);
    try array_list.append(allocator, 1);

    sequence = Sequence(u8, null).fromOwnedSlice(try array_list.toOwnedSlice(allocator));
    try std.testing.expectEqualSlices(u8, sequence.asSlice(), &.{ 4, 3, 2, 1 });

    sequence.deinit(allocator);

    try sequence.append(allocator, 10);
    try sequence.append(allocator, 9);
    array_list = sequence.toArrayList();
    try std.testing.expectEqual(0, sequence.size);
    try std.testing.expectEqual(0, sequence.capacity);

    try array_list.append(allocator, 8);
    try array_list.append(allocator, 7);
    try array_list.append(allocator, 6);
    try array_list.append(allocator, 5);

    sequence = .fromArrayList(&array_list);
    try std.testing.expectEqual(0, array_list.capacity);
    try std.testing.expectEqualSlices(u8, sequence.asSlice(), &.{ 10, 9, 8, 7, 6, 5 });
    sequence.deinit(allocator);
}

test "Test sequence rcl allocator" {
    const RclAllocator = @import("./allocator.zig").RclAllocator;
    var allocator = std.testing.allocator;
    const rcl_allocator = RclAllocator.initFromZig(&allocator);
    var sequence = Sequence(u8, null).empty;
    errdefer sequence.deinit(rcl_allocator);

    try sequence.reserve(rcl_allocator, 6);
    try sequence.append(rcl_allocator, 5);
    try sequence.append(rcl_allocator, 6);
    try sequence.append(rcl_allocator, 7);
    try sequence.append(rcl_allocator, 8);
    try std.testing.expectEqualSlices(u8, sequence.asSlice(), &.{ 5, 6, 7, 8 });

    sequence.deinit(rcl_allocator);
}

test "Test sequence with structure that requires init deinit" {
    const TestStruct = struct {
        const Self = @This();
        sequence: []u8,

        pub fn init(alloc: anytype) !Self {
            const to_return = Self{ .sequence = try alloc.alloc(u8, 5) };
            to_return.sequence[0] = 10;
            to_return.sequence[1] = 11;
            to_return.sequence[2] = 12;
            to_return.sequence[3] = 13;
            to_return.sequence[4] = 14;
            return to_return;
        }

        pub fn deinit(self: *Self, alloc: anytype) void {
            alloc.free(self.sequence);
        }
    };
    const allocator = std.testing.allocator;

    var sequence = Sequence(TestStruct, null).empty;
    errdefer sequence.deinit(allocator);

    // deinit should be safe to call even on fresh structure
    sequence.deinit(allocator);

    const new_element = try sequence.addOne(allocator);
    try std.testing.expectEqualSlices(u8, new_element.sequence, &.{ 10, 11, 12, 13, 14 });

    var new_struct = TestStruct{ .sequence = try allocator.alloc(u8, 2) };
    {
        errdefer new_struct.deinit(allocator);
        new_struct.sequence[0] = 20;
        new_struct.sequence[1] = 21;

        try sequence.append(allocator, new_struct);
    }

    try std.testing.expectEqualSlices(u8, sequence.asSlice()[0].sequence, &.{ 10, 11, 12, 13, 14 });
    try std.testing.expectEqualSlices(u8, sequence.asSlice()[1].sequence, &.{ 20, 21 });

    sequence.deinit(allocator);
}

test "Test bound sequence" {
    const allocator = std.testing.allocator;
    const BoundSequence = Sequence(u8, 4);
    var sequence = BoundSequence.empty;
    errdefer sequence.deinit(allocator);
    // empty deinit should be safe
    sequence.deinit(allocator);

    try sequence.append(allocator, 1);
    try sequence.append(allocator, 2);
    try sequence.append(allocator, 3);
    try sequence.append(allocator, 4);
    try std.testing.expectEqualSlices(u8, sequence.asSlice(), &.{ 1, 2, 3, 4 });
    try std.testing.expectError(SequenceError.AtUpperBound, sequence.append(allocator, 5));

    sequence.deinit(allocator);

    var array_list = std.ArrayListUnmanaged(u8).empty;
    defer array_list.deinit(allocator);
    try array_list.append(allocator, 5);
    try array_list.append(allocator, 4);
    try array_list.append(allocator, 3);
    try array_list.append(allocator, 2);
    try array_list.append(allocator, 1);

    // note since from owned slice can error on bound sequences its important to keep track of the
    // owned pointer so its not lost on error.
    const owned = try array_list.toOwnedSlice(allocator);
    try std.testing.expectError(SequenceError.AtUpperBound, BoundSequence.fromOwnedSlice(owned));
    allocator.free(owned);
}
