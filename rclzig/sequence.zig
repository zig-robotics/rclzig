const std = @import("std");
const trait = @import("trait.zig");

const SequenceError = error{
    AtUpperBound,
};

pub fn Sequence(comptime T: type, comptime upper_bound: ?usize) type {
    return extern struct {
        const Self = @This();
        data: [*]T = undefined,
        size: usize = 0,
        capacity: usize = 0,

        pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {
            // TODO this assumes we only ever receive builtin zig types or ROS messages as structs.
            // Do better, be defensive? support other types?
            // TODO test this?
            if (comptime trait.hasDeinitWithAllocator(T)) {
                var i: usize = 0;
                while (i < self.size) : (i += 1) {
                    self.data[i].deinit(allocator);
                }
            }
            if (self.capacity > 0) {
                allocator.free(self.data[0..self.capacity]);
            }
        }

        pub fn append(self: *Self, allocator: std.mem.Allocator, new_value: T) !void {
            // TODO does this work for complex structures (ones with pointers?)
            (try self.add(allocator)).* = new_value;
        }

        // TODO pick better name than add for this?
        // TODO should this call init if it exists?
        // TODO we should probably only return initialized values if we're going to automate the deinit
        // TODO or maybe we leave the raw sexquence interface real dumb and force the inevitable wrapper
        // class (the one which is managed)
        pub fn add(self: *Self, allocator: std.mem.Allocator) !*T {
            // TODO this seems like it might be bad
            var new_data: *T = undefined;
            if (self.size < self.capacity) {
                self.size += 1;
                new_data = &self.data[self.size];
            } else {
                if (upper_bound) |bound| {
                    if (self.capacity == bound) {
                        return SequenceError.AtUpperBound;
                    }
                }

                self.data = (try allocator.realloc(self.data[0..self.size], self.capacity + 1)).ptr;
                self.capacity += 1;
                self.size = self.capacity;
                new_data = &self.data[self.size];
            }
            if (comptime trait.hasInitWithAllocator(T)) {
                try new_data.init(allocator);
            }
            return new_data;
        }

        // TODO this should reclect capacity some how?
        pub fn reserve(self: *Self, allocator: std.mem.Allocator, size: usize) !void { // TODO return something?
            if (size > self.capacity) {
                try allocator.realloc(self.data, size);
                self.capacity = size;
                // TODO should this modify size in any instances?
            }
        }
    };
}

// TODO sequence test
// const Test = Sequence(u8, 4);

// var asdf = Test{};
// defer asdf.deinit(allocator);
// _ = try asdf.add(allocator);
// _ = try asdf.add(allocator);
// _ = try asdf.add(allocator);
// _ = try asdf.add(allocator);
// _ = try asdf.add(allocator);

// std.log.debug("asdf: {}", .{asdf});
