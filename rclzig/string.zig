const std = @import("std");

// ROS strings are sequences where size is always equal to capacity - 1 where the final value is a null terminator
// This type takes a generic allocator. This is to allow the user to decide if its backed by a zig
// or rcl allocator. The allocator type must implement alloc, realloc, and free and match the zig
// allocator signature. The RclAllocator type provides these abstractions around the rcl allocator.
//
// For types that touch the rmw its important to stick to the default rcl allocator. This means
// messages used in the `take` functions (rcl_take, rcl_take_request rcl_take_response) for
// subscriptions, services, and actions must be initialized and deinitialized with the default
// rcl allocator (or whatever allocator the rmw is using, in pretty much all cases its just malloc)
pub const RosString = extern struct {
    const Self = @This();
    data: [*]u8 = undefined,
    size: usize = 0,
    capacity: usize = 0,
    // TODO non trivial ROS messages (fields that need init called) probably shouldn't allow for defaults
    // data: [*]u8,
    // size: usize,
    // capacity: usize,

    pub fn init(allocator: anytype) !Self {
        var return_type = Self{
            .data = (try allocator.alloc(u8, 1)).ptr,
            .capacity = 1,
            .size = 0,
        };
        return_type.data[0] = 0;
        return return_type;
    }

    pub fn deinit(self: *Self, allocator: anytype) void {
        if (self.capacity > 0) {
            allocator.free(self.data[0..self.capacity]);
        }
        self.capacity = 0;
        self.size = 0;
    }

    pub fn asSlice(self: *const Self) []u8 {
        return self.data[0..self.size];
    }

    pub fn asSliceSentinel(self: *const Self) [:0]u8 {
        return self.data[0..self.size :0];
    }

    pub fn addOne(self: *Self, allocator: anytype) !*u8 {
        std.debug.assert(self.capacity == self.size + 1); // check that this has been initialized
        self.data = (try allocator.realloc(self.data[0..self.capacity], self.capacity + 1)).ptr;
        self.capacity += 1;
        self.size += 1;
        self.data[self.size] = 0;
        return &self.data[self.size - 1];
    }

    pub fn append(self: *Self, allocator: anytype, new_value: u8) !void {
        (try self.addOne(allocator)).* = new_value;
    }

    pub fn appendSlice(self: *Self, allocator: anytype, new_slice: []const u8) !void {
        // assert that string is inited
        std.debug.assert(self.capacity == self.size + 1);
        const slice = try allocator.realloc(self.data[0..self.capacity], self.capacity + new_slice.len);
        @memcpy(slice[self.size..][0..new_slice.len], new_slice);
        slice[slice.len - 1] = 0;
        self.data = slice.ptr;
        self.capacity = slice.len;
        self.size = self.capacity - 1;
    }

    pub fn assign(self: *Self, allocator: anytype, new_value: []const u8) !void {
        std.debug.assert(self.capacity == self.size + 1); // check that this has been initialized
        self.data = (try allocator.realloc(self.data[0..self.capacity], new_value.len + 1)).ptr;
        @memcpy(self.data, new_value);
        self.data[new_value.len] = 0;
        self.capacity = new_value.len + 1;
        self.size = self.capacity - 1;
    }

    // If the provided slice is not null terminated this will call resize on the passed slice
    // See from owned slice sentinel to guarentee no realloc
    // Note the original allocator must continue to be used with following calls
    pub fn fromOwnedSlice(allocator: anytype, owned: []u8) !Self {
        if (owned[owned.len - 1] == 0) {
            return RosString.fromOwnedSliceSentinel(owned[0 .. owned.len - 1 :0]);
        } else {
            return .{
                .data = blk: {
                    const data = try allocator.realloc(owned, owned.len + 1);
                    data[owned.len] = 0;
                    break :blk data.ptr;
                },
                .size = owned.len,
                .capacity = owned.len + 1,
            };
        }
    }

    // The string assumes ownership of the passed slice.
    // Following calls must use the same allocator that the original slice was created with
    pub fn fromOwnedSliceSentinel(owned: [:0]u8) Self {
        return .{
            .data = owned.ptr,
            .size = owned.len,
            .capacity = owned.len + 1,
        };
    }
};

test "test ros string" {
    var allocator = std.testing.allocator;

    // Test rcl allocator
    const RclAllocator = @import("./allocator.zig").RclAllocator;
    const rcl_allocator = RclAllocator.initFromZig(&allocator);

    var string = try RosString.init(rcl_allocator);
    errdefer string.deinit(rcl_allocator);
    try std.testing.expectEqual(0, string.data[0]);
    try std.testing.expectEqual(0, string.size);
    try std.testing.expectEqual(1, string.capacity);

    try string.append(rcl_allocator, 'a');
    try std.testing.expectEqual('a', string.data[0]);
    try std.testing.expectEqual(0, string.data[1]);
    try std.testing.expectEqual(1, string.size);
    try std.testing.expectEqual(2, string.capacity);
    string.deinit(rcl_allocator);

    string = try RosString.init(rcl_allocator);
    try string.appendSlice(rcl_allocator, "test");
    try std.testing.expectEqualSlices(u8, "test", string.asSlice());
    try std.testing.expectEqualSentinel(u8, 0, "test", string.asSliceSentinel());
    try string.appendSlice(rcl_allocator, "wow");
    try std.testing.expectEqualSentinel(u8, 0, "testwow", string.asSliceSentinel());
    string.deinit(rcl_allocator);

    string = try RosString.init(rcl_allocator);
    try string.assign(rcl_allocator, "test");
    try std.testing.expectEqualSentinel(u8, 0, "test", string.asSliceSentinel());
    string.deinit(rcl_allocator);

    // Test zig allocator
    const new_string = try allocator.dupe(u8, "hello");
    {
        errdefer allocator.free(new_string);
        string = try RosString.fromOwnedSlice(allocator, new_string);
    }
    try std.testing.expectEqualSentinel(u8, 0, "hello", string.asSliceSentinel());
    string.deinit(allocator);

    var array_list = std.ArrayListUnmanaged(u8){};
    try array_list.appendSlice(allocator, "goodbye");
    {
        errdefer array_list.deinit(allocator);
        try array_list.append(allocator, 0);
        string = try RosString.fromOwnedSlice(
            std.testing.failing_allocator, // should never allocate
            try array_list.toOwnedSlice(allocator),
        );
    }
    try std.testing.expectEqualSentinel(u8, 0, "goodbye", string.asSliceSentinel());
    string.deinit(allocator);

    const c_string = try allocator.dupeZ(u8, "goodbye");
    string = RosString.fromOwnedSliceSentinel(c_string);
    try std.testing.expectEqualSentinel(u8, 0, "goodbye", string.asSliceSentinel());
    string.deinit(allocator);
}
