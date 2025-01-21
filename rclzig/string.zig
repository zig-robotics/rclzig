const std = @import("std");

// TODO STRINGS?
// Strings seem to basically be sequences that are guarenteed null terminated.
// I'm not quite shure of the friendliest way to implement this
// I'd rather not re-implement the sequence entirely?
// TODO the bounded string type is treated as a "base type" and can be in arrays. It should probably be treated as such?
// This can copy the sequence type for an optional bound
const RosString = struct {
    const Self = @This();
    data: [*]u8 = undefined,
    size: usize = 0,
    capacity: usize = 0,

    pub fn init(allocator: std.mem.Allocator) !Self {
        var return_type = Self{};
        var new_value = try return_type.add(allocator);
        new_value.size = 0;
        new_value.capacity = 1;
        return return_type;
    }

    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
        // TODO this assumes we only ever receive builtin zig types or ROS messages as structs.
        // Do better, be defensive? support other types?
        // TODO test this?
        if (self.capacity > 0) {
            allocator.free(self.data[0..self.capacity]);
        }
    }

    pub fn append(self: *Self, allocator: std.mem.Allocator, new_value: u8) !void {
        // TODO does this work for complex structures (ones with pointers?)
        (try self.add(allocator)).* = new_value;
    }

    // TODO pick better name than add for this?
    // TODO should this call init if it exists?
    // TODO we should probably only return initialized values if we're going to automate the deinit
    // TODO or maybe we leave the raw sexquence interface real dumb and force the inevitable wrapper
    // class (the one which is managed)
    pub fn add(self: *Self, allocator: std.mem.Allocator) !*u8 {
        // TODO this seems like it might be bad
        var new_data: *u8 = undefined;
        if (self.size < self.capacity + 1) {
            self.size += 1;
            new_data = self.data[self.size];
            self.data[self.size + 1] = 0;
        } else {
            self.data = (try allocator.realloc(self.data[0..self.capacity], self.capacity + 1)).ptr;
            self.capacity += 1;
            self.size += 1;
            new_data = self.data[self.size];
        }
        return new_data;
    }

    // TODO finish this?
    pub fn assign(self: *Self, allocator: std.mem.Allocator, new_value: [:0]const u8) !void {
        self.data = (try allocator.realloc(self.data[0..self.capacity], new_value.len)).ptr;
        @memcpy(self.data, new_value);
        self.capacity = new_value.len;
        self.size = self.capacity - 1;
    }
};

