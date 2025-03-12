const std = @import("std");
const builtin = @import("builtin");

const sequence = @import("sequence.zig");
const file_format =
    \\const std = @import("std");
    \\const rosidl_runtime = @import("rclzig").rosidl_runtime;
    \\{[additional_imports]s}
    \\
    \\extern fn rosidl_typesupport_c__get_message_type_support_handle__{[package_name]s}__msg__{[msg_type]s}() *const rosidl_runtime.RosidlMessageTypeSupport;
    \\
    \\pub const {[msg_type]s} = extern struct {{
    \\    const Self = @This();
    \\{[struct_payload]s}
    \\{[init_body]s}
    \\{[deinit_body]s}
    \\    pub fn getTypeSupportHandle() *const rosidl_runtime.RosidlMessageTypeSupport {{
    \\        return rosidl_typesupport_c__get_message_type_support_handle__{[package_name]s}__msg__{[msg_type]s}();
    \\    }}
    \\}};
;

// TODO: general things that are still missing
// String constants
// Bounded strings
// Wide strings
// Lots of testing?
// Turn into build tools, follow (https://ziglang.org/learn/build-system/#running-the-projects-tools)
// and here https://ziglang.org/learn/build-system/#generating-zig-source-code

const MessageMetadata = struct {
    struct_payload: []const u8,
    msg_type: []const u8,
    package_name: []const u8,
    init_body: []const u8,
    deinit_body: []const u8,
    additional_imports: []const u8,
};

// TODO this is used for naming complex  types as well, the function should probably have a better name
fn getKey(allocator: std.mem.Allocator, package: []const u8, msg: []const u8) ![]const u8 {
    return try std.fmt.allocPrint(allocator, "{s}.msg.{s}", .{ package, msg });
}

const DataEntries = struct {
    const Self = @This();
    const Entry = struct {
        const BaseType = enum {
            const ZigType = enum {
                bool,
                f32,
                f64,
                i8,
                u8,
                i16,
                u16,
                i32,
                u32,
                i64,
                u64,
                RosString,
            };
            pub fn zigType(self: BaseType) ZigType {
                switch (self) {
                    .bool => return ZigType.bool,
                    .byte => return ZigType.u8,
                    .char => return ZigType.u8,
                    .float32 => return ZigType.f32,
                    .float64 => return ZigType.f64,
                    .int8 => return ZigType.i8,
                    .uint8 => return ZigType.u8,
                    .int16 => return ZigType.i16,
                    .uint16 => return ZigType.u16,
                    .int32 => return ZigType.i32,
                    .uint32 => return ZigType.u32,
                    .int64 => return ZigType.i64,
                    .uint64 => return ZigType.u64,
                    .string => return ZigType.RosString,
                    // .wstring,
                }
            }
            bool,
            byte,
            char,
            float32,
            float64,
            int8,
            uint8,
            int16,
            uint16,
            int32,
            uint32,
            int64,
            uint64,
            string,
            // wstring,
        };

        const Type = union(enum) {
            pub fn name(self: Type) []const u8 {
                switch (self) {
                    .base_type => |base_type| return @ptrCast(@tagName(base_type.zigType())),
                    .complex_type => |complex_type| return complex_type,
                }
            }
            base_type: BaseType,
            complex_type: []const u8,
        };

        // TODO this seems like it could be a tagged union
        const ArrayType = struct {
            const Kind = enum {
                static_array,
                unbounded_dynamic_array,
                bounded_dynamic_array,
                bounded_string, // TODO bounded strings
            };

            kind: Kind,
            size: usize,
        };

        data_type: Type,
        array_type: ?ArrayType,
        is_constant: bool,
        name: []const u8,
        default: []const u8,
    };

    pub fn create(allocator: std.mem.Allocator, message_name: []const u8, package_name: []const u8) !*Self {
        const to_return = try allocator.create(Self);
        to_return.* = .{
            .entries = std.ArrayListUnmanaged(Entry){},
            .dependencies = std.StringArrayHashMapUnmanaged(void){},
            .message_name = try std.fmt.allocPrint(allocator, "{s}", .{message_name}),
            .package_name = try std.fmt.allocPrint(allocator, "{s}", .{package_name}),
            .key = try getKey(allocator, package_name, message_name),
        };
        return to_return;
    }

    pub fn addEntry(
        self: *Self,
        allocator: std.mem.Allocator,
        data_type: Entry.Type,
        array_type_in: ?Entry.ArrayType,
        is_constant: bool,
        name: []const u8,
        default_in: ?[]const u8,
        loaded_messages: *const std.StringArrayHashMap(*DataEntries),
    ) !void {
        var new_entry = try self.entries.addOne(allocator);
        new_entry.* = .{
            .data_type = data_type,
            .array_type = array_type_in,
            .is_constant = is_constant,
            .name = try allocator.dupe(u8, name),
            .default = undefined,
        };

        if (default_in) |default| {
            new_entry.default = try allocator.dupe(u8, default);
        } else {
            if (array_type_in) |array_type| switch (array_type.kind) {
                .static_array => {
                    var result = std.ArrayListUnmanaged(u8){};
                    try result.appendSlice(allocator, "[ ");
                    for (0..array_type.size) |_| {
                        switch (data_type) {
                            // TODO check if init is required?
                            .complex_type => try result.appendSlice(allocator, ".{}, "),
                            .base_type => |base_type| switch (base_type.zigType()) {
                                .bool => try result.appendSlice(allocator, "false, "),
                                .RosString => try result.appendSlice(allocator, ".{}, "),
                                else => try result.appendSlice(allocator, "0, "),
                            },
                        }
                    }
                    try result.appendSlice(allocator, "]");
                    new_entry.default = result.items;
                },
                .unbounded_dynamic_array => new_entry.default = "",
                .bounded_dynamic_array => new_entry.default = "",
                .bounded_string => new_entry.default = "TODO",
            } else switch (data_type) {
                .base_type => |base_type| switch (base_type.zigType()) {
                    .bool => new_entry.default = "false",
                    .RosString => new_entry.default = "",
                    else => new_entry.default = "0",
                },
                .complex_type => |t| new_entry.default = if (loaded_messages.get(t).?.initRequired(loaded_messages)) "" else ".{}",
            }
        }
    }

    pub fn additionalImports(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayListUnmanaged(u8){};
        var writer = result.writer(allocator);
        var imports = std.StringHashMap(void).init(allocator);
        // const rcl_allocator_import = "const RclAllocator = @import(\"rclzig\").RclAllocator;\n";
        for (self.entries.items) |entry| {
            if (entry.array_type) |array_type| {
                switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array, .bounded_string => {
                        const sequence_import = "const Sequence = @import(\"rclzig\").Sequence;\n";
                        if (!imports.contains(sequence_import)) {
                            try imports.put(sequence_import, void{});
                            try writer.writeAll(sequence_import);
                        }
                        // TODO remove after test
                        // if (!imports.contains(rcl_allocator_import)) {
                        //     try imports.put(rcl_allocator_import, void{});
                        //     try writer.writeAll(rcl_allocator_import);
                        // }
                    },
                    .static_array => {},
                }
            }
            switch (entry.data_type) {
                .complex_type => |data_type| {
                    var package_it = std.mem.tokenizeScalar(u8, data_type, '.');
                    const package = package_it.next().?;
                    if (!imports.contains(package)) {
                        try imports.put(package, void{});
                        try writer.print("const {[package]s} = @import(\"{[package]s}\");\n", .{ .package = package });
                    }
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        const string_import = "const RosString = @import(\"rclzig\").RosString;\n";
                        if (!imports.contains(string_import)) {
                            try imports.put(string_import, void{});
                            try writer.writeAll(string_import);
                        }
                        // TODO remove after test
                        // if (!imports.contains(rcl_allocator_import)) {
                        //     try imports.put(rcl_allocator_import, void{});
                        //     try writer.writeAll(rcl_allocator_import);
                        // }
                    },
                    else => {},
                },
            }
        }
        return result.items;
    }

    pub fn payload(self: *Self, allocator: std.mem.Allocator) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        var writer = result.writer();
        for (self.entries.items) |entry| {
            if (entry.is_constant) {
                // TODO switch to list of entries and list of const entires to remove double loop and if
                try writer.print("    const {s}: {s} = {s};\n", .{ entry.name, @tagName(entry.data_type.base_type.zigType()), entry.default });
            }
        }
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                try writer.print("    {s}: ", .{entry.name});
                if (entry.array_type) |array_type| {
                    switch (array_type.kind) {
                        .unbounded_dynamic_array => {
                            try writer.print("Sequence({s}, null) = .empty,\n", .{entry.data_type.name()});
                        },
                        .bounded_dynamic_array => {
                            try writer.print("Sequence({s}, {}) = .empty,\n", .{ entry.data_type.name(), array_type.size });
                        },
                        .static_array => {
                            try writer.print("[{[size]}]{[type]s} = [_]{[type]s}{{ ", .{ .size = array_type.size, .type = entry.data_type.name() });
                            var i: usize = 0;
                            var token_it = std.mem.tokenizeAny(u8, entry.default, "[ ,]");
                            while (token_it.next()) |token| : (i += 1) {
                                // TODO assert length requirement
                                try writer.print("{s}, ", .{token});
                            }
                            // TODO consider some sanity checks?
                            writer.context.shrinkRetainingCapacity(result.items.len - 2); // remove last coma
                            try writer.writeAll(" },\n");
                        },
                        .bounded_string => return error.BoundedStringsArentImplemented,
                    }
                } else switch (entry.data_type) {
                    .base_type => |data_type| switch (data_type) {
                        // TODO if there's a string, this must be called via init and should not have a default
                        .string => try writer.print("{s},\n", .{entry.data_type.name()}),
                        else => try writer.print("{s} = {s},\n", .{ entry.data_type.name(), entry.default }),
                    },
                    else => if (entry.default.len == 0)
                        try writer.print("{s},\n", .{entry.data_type.name()})
                    else
                        try writer.print("{s} = {s},\n", .{ entry.data_type.name(), entry.default }),
                }
            }
        }
        return result.items;
    }

    pub fn initFunction(self: *Self, allocator: std.mem.Allocator, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        var writer = result.writer();

        try writer.writeAll("    pub fn init(allocator: anytype) !Self {\n");
        try writer.writeAll("        var return_value: Self = .{\n");
        for (self.entries.items) |entry| if (!entry.is_constant) {
            if (entry.array_type) |array_type| switch (array_type.kind) {
                else => {},
                //     .static_array => switch (entry.data_type) {
                //         .complex_type => |data_type| if (loaded_messages.get(data_type).?.initRequired(loaded_messages)) {
                //             // TODO in zig 0.14 this can be made nicer with just '.init(allocator);'
                //             try writer.print("        for(return_value.{s}) |*entry| entry.* = try {s}.init(allocator);\n", .{ entry.name, data_type });
                //         },
                //         .base_type => |data_type| switch (data_type.zigType()) {
                //             .RosString => try writer.print("        for(return_value.{s}) |*entry| entry.* = try RosString.init(allocator);\n", .{entry.name}),
                //             else => {},
                //         },
                //     },
                //     .unbounded_dynamic_array, .bounded_dynamic_array => {
                //         var token_it = std.mem.tokenizeAny(u8, entry.default, "[ ,]");
                //         // TODO switch to assign? (don't individually append)
                //         while (token_it.next()) |token| {
                //             try writer.print("        return_value.{s}.append(allocator, {s});\n", .{ entry.name, token });
                //         }
                //     },
                //     .bounded_string => {}, // TODO bounded strings
            } else switch (entry.data_type) {
                .complex_type => |data_type| {
                    if (loaded_messages.get(data_type).?.initRequired(loaded_messages)) {
                        try writer.print("            .{s} = undefined,\n", .{entry.name});
                    }
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        try writer.print("            .{s} = .uninitialized,\n", .{entry.name});
                    },
                    else => {},
                },
            }
        };
        try writer.writeAll("        };\n");
        for (self.entries.items) |entry| if (!entry.is_constant) {
            if (entry.array_type) |array_type| switch (array_type.kind) {
                .static_array => switch (entry.data_type) {
                    // TODO figure out errdefer deinit on members?
                    .complex_type => |data_type| if (loaded_messages.get(data_type).?.initRequired(loaded_messages)) {
                        try writer.print("        for(return_value.{s}) |*entry| entry.* = try .init(allocator);\n", .{entry.name});
                    },
                    .base_type => |data_type| switch (data_type.zigType()) {
                        .RosString => try writer.print("        for(return_value.{s}) |*entry| entry.* = try .init(allocator);\n", .{entry.name}),
                        else => {},
                    },
                },
                .unbounded_dynamic_array, .bounded_dynamic_array => {
                    var token_it = std.mem.tokenizeAny(u8, entry.default, "[ ,]");
                    // TODO switch to assign? (don't individually append)
                    while (token_it.next()) |token| {
                        try writer.print("        return_value.{s}.append(allocator, {s});\n", .{ entry.name, token });
                    }
                },
                .bounded_string => {}, // TODO bounded strings
            } else switch (entry.data_type) {
                .complex_type => |data_type| {
                    if (loaded_messages.get(data_type).?.initRequired(loaded_messages)) {
                        try writer.print("        return_value.{s} = try .init(allocator);\n", .{entry.name});
                        if (loaded_messages.get(data_type).?.deinitRequired(loaded_messages)) {
                            try writer.print("        errdefer return_value.{s}.deinit(allocator);\n", .{entry.name});
                        }
                    }
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        try writer.print("        return_value.{s} = try .init(allocator);\n", .{entry.name});
                        try writer.print("        errdefer return_value.{s}.deinit(allocator);\n", .{entry.name});
                        if (entry.default.len > 0) {
                            try writer.print("        try return_value.{s}.assign(allocator, {s});\n", .{ entry.name, entry.default });
                        }
                    },
                    else => {},
                },
            }
        };

        try writer.writeAll("        return return_value;\n");
        try writer.writeAll("    }\n");

        return result.items;
    }

    pub fn deinitFunction(self: *Self, allocator: std.mem.Allocator, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) ![]u8 {
        var result = std.ArrayList(u8).init(allocator);
        var writer = result.writer();

        try writer.writeAll("    pub fn deinit(self: *Self, allocator: anytype) void {\n");
        for (self.entries.items) |entry| if (!entry.is_constant) {
            if (entry.array_type) |array_type| switch (array_type.kind) {
                .static_array => {
                    switch (entry.data_type) {
                        .complex_type => |data_type| {
                            if (loaded_messages.get(data_type).?.deinitRequired(loaded_messages)) {
                                try writer.print("        for(self.{s}) |*entry| entry.deinit(allocator);\n", .{entry.name});
                            }
                        },
                        .base_type => |data_type| switch (data_type.zigType()) {
                            .RosString => try writer.print("        for(self.{s}) |*entry| entry.deinit(allocator);\n", .{entry.name}),
                            else => {},
                        },
                    }
                },
                .unbounded_dynamic_array, .bounded_dynamic_array => {
                    try writer.print("        self.{s}.deinit(allocator);\n", .{entry.name});
                },
                .bounded_string => {},
            } else switch (entry.data_type) {
                .complex_type => |data_type| if (loaded_messages.get(data_type).?.deinitRequired(loaded_messages)) {
                    try writer.print("        self.{s}.deinit(allocator);\n", .{entry.name});
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        try writer.print("        self.{s}.deinit(allocator);\n", .{entry.name});
                    },
                    else => {},
                },
            }
        };
        try writer.writeAll("    }\n");
        return result.items;
    }

    fn dependencyRequiresInit(self: Self, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) bool {
        var dependencies_it = self.dependencies.iterator();
        while (dependencies_it.next()) |dependency| {
            if (loaded_messages.get(dependency).?.initRequired()) return true;
        }
        return false;
    }

    fn dependencyRequiresDeinit(self: Self, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) bool {
        var dependencies_it = self.dependencies.iterator();
        while (dependencies_it.next()) |dependency| {
            if (loaded_messages.get(dependency).?.deinitRequired()) return true;
        }
        return false;
    }

    pub fn initRequired(self: Self, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) bool {
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                if (entry.array_type) |array_type| switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array => {
                        if (entry.default.len != 0) return true;
                    }, // TODO add bounded string
                    else => {},
                } else {
                    switch (entry.data_type) {
                        .complex_type => |data_type| {
                            if (loaded_messages.get(data_type).?.initRequired(loaded_messages)) return true;
                        },
                        .base_type => |data_type| switch (data_type.zigType()) {
                            .RosString => return true,
                            else => {},
                        },
                    }
                }
            }
        }
        return false;
    }

    pub fn deinitRequired(self: Self, loaded_messages: *const std.StringArrayHashMap(*DataEntries)) bool {
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                switch (entry.data_type) {
                    .complex_type => |data_type| if (loaded_messages.get(data_type).?.deinitRequired(loaded_messages)) return true,
                    .base_type => |data_type| switch (data_type.zigType()) {
                        .RosString => return true,
                        else => {},
                    },
                }
                if (entry.array_type) |array_type| switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array => return true, // TODO add bounded strings
                    else => {},
                };
            }
        }
        return false;
    }

    pub fn addLine(
        self: *Self,
        allocator: std.mem.Allocator,
        loaded_messages: *std.StringArrayHashMap(*DataEntries),
        line: []const u8,
        source_package: []const u8,
        dependencies: *const std.StringArrayHashMap([]const u8),
    ) !void {
        var line_it = std.mem.tokenizeScalar(u8, line, ' '); // we can't tokenize on = because its used to declare bounded arrays
        const data_type_optional = line_it.next();
        var data_type_str: []const u8 = undefined;
        if (data_type_optional) |data_type_real| {
            data_type_str = data_type_real;
        } else {
            return;
        }
        var new_type_optional: ?DataEntries.Entry.BaseType = null;

        if (std.mem.startsWith(u8, data_type_str, "#")) {
            return;
        }

        inline for (@typeInfo(DataEntries.Entry.BaseType).@"enum".fields) |field| {
            if (std.mem.startsWith(u8, data_type_str, field.name)) {
                new_type_optional = @enumFromInt(field.value);
            }
        }

        var new_type: DataEntries.Entry.Type = undefined;
        if (new_type_optional) |new_type_real| {
            new_type = .{ .base_type = new_type_real };
        } else {
            // New type is a complex type, if there is a slash it is an external type, no slash and it's an internal type
            var package: []const u8 = undefined;
            var msg: []const u8 = undefined;
            if (std.mem.count(u8, data_type_str, "/") == 1) {
                var it = std.mem.tokenizeAny(u8, data_type_str, "/[]"); // tokenizing on square brackets as lazy way to remove any array marker
                package = it.next().?;
                msg = it.next().?;
            } else {
                package = source_package;
                var it = std.mem.tokenizeAny(u8, data_type_str, "/[]"); // tokenizing on square brackets as lazy way to remove any array marker
                msg = it.next().?;
            }

            new_type = .{ .complex_type = try getKey(allocator, package, msg) };

            const new_type_path = try std.fmt.allocPrint(
                allocator,
                "{s}/msg/{s}.msg",
                .{ dependencies.get(package) orelse {
                    std.log.err(
                        "Generating message {s} requires dependency {s}, but that dependency was not found",
                        .{ self.message_name, package },
                    );
                    return LoadRosMessageError.CantFindPackageError;
                }, msg },
            );
            // Just need to make sure the message is loaded for later use, do nothing with the result.
            const dependency = loaded_messages.get(new_type.complex_type) orelse
                try loadRosMessage(allocator, loaded_messages, new_type_path, package, dependencies);
            try self.dependencies.put(allocator, dependency.key, {});
            // catch |err| switch (err) {
            // TODO this logic is for the search paths version, add back in when readding search paths.
            // error.CantFindPackageError => {
            //     std.log.err(
            //         "Can't find package \"{s}\" in search paths \"{s}\" that message \"{s}\" depends on.",
            //         .{ package, dependency_search_paths, self.message_name },
            //     );
            //     return LoadRosMessageError.CantFindMessageDependencyError;
            // },
            // error.CantFindMessageError => {
            //     std.log.err(
            //         "Can't find message \"{s}\" in package \"{s}\" that message \"{s}\" depends on.",
            //         .{ msg, package, self.message_name },
            //     );
            //     return LoadRosMessageError.CantFindMessageDependencyError;
            // },
            // else => return err,
            // };
        }

        var new_array_type: ?DataEntries.Entry.ArrayType = null; // TODO array type
        if (std.mem.indexOfAny(u8, data_type_str, "[")) |open_index| {
            if (std.mem.indexOfAny(u8, data_type_str, "]")) |close_index| {
                var array_type_raw = std.mem.trim(u8, data_type_str[open_index + 1 .. close_index], " ");
                if (array_type_raw.len == 0) {
                    new_array_type = DataEntries.Entry.ArrayType{
                        .kind = DataEntries.Entry.ArrayType.Kind.unbounded_dynamic_array,
                        .size = 0,
                    };
                } else if (std.mem.count(u8, array_type_raw, "<=") == 1) {
                    if (array_type_raw.len > 2) {
                        new_array_type = DataEntries.Entry.ArrayType{
                            .kind = DataEntries.Entry.ArrayType.Kind.bounded_dynamic_array,
                            .size = try std.fmt.parseInt(usize, array_type_raw[2..array_type_raw.len], 0),
                        };
                    } else {
                        // TODO error
                    }
                } else {
                    // Assume static array.
                    new_array_type = DataEntries.Entry.ArrayType{
                        .kind = DataEntries.Entry.ArrayType.Kind.static_array,
                        .size = try std.fmt.parseInt(usize, array_type_raw, 0),
                    };
                }
            } else {
                // TODO error
            }
        }
        var name_it = std.mem.tokenizeAny(u8, line[line_it.index..line.len], " ="); // Now we can tokenize on space and equal because we're past type definitions
        if (name_it.next()) |name| {
            const new_name: []const u8 = name;
            var new_value: ?[]const u8 = null;
            const new_is_constant = isUppercase(name);
            if (name_it.next()) |value| {
                if (std.mem.startsWith(u8, value, "#")) {
                    if (new_is_constant) {
                        // TODO Error handling
                    }
                } else {
                    var value_it = std.mem.tokenizeAny(u8, name_it.buffer[name_it.index - value.len .. name_it.buffer.len], "[]#");
                    new_value = value_it.next();
                }
            } else if (new_is_constant) {
                // TODO Constants must have a value, this is an error
            }
            try self.addEntry(allocator, new_type, new_array_type, new_is_constant, new_name, new_value, loaded_messages);
        }
    }
    entries: std.ArrayListUnmanaged(Entry),
    dependencies: std.StringArrayHashMapUnmanaged(void),
    message_name: []const u8,
    package_name: []const u8,
    key: []const u8,
};

pub fn isUppercase(string: []const u8) bool {
    for (string) |character| {
        if (std.ascii.isAlphabetic(character) and std.ascii.isLower(character)) {
            return false;
        }
    }
    return true;
}

// Message should be the fully qualified string which includes package, ex "std_msgs/msg/Header"
// search_paths should be colon separated list. This can match exactly the AMENT_PREFIX_PATH environment variable in a normal ROS environment
// When in doubt, it should be "/opt/ros/{ros version name}"i
const LoadRosMessageError = error{
    CantFindPackageError,
    CantFindMessageError,
    CantFindMessageDependencyError,
    MalformedMessageInputError,
    // AllocPrintError,
    //  File.OpenError,
    //     IteratorError = error{ AccessDenied, SystemResources } || os.UnexpectedError,
    // Allocator.Error,
    // ParseIntError,
} || std.mem.Allocator.Error || std.fmt.AllocPrintError || std.fs.Dir.Iterator.Error || std.fmt.ParseIntError || std.fs.File.OpenError || std.fs.File.ReadError;
// TODO figure out error set buisness. above is a lazy list of all possible erros thrown with basic trys.
// Some of these probably make sense to aliase to more generic laond message error (parse int error for example doesn't mean much, while allocator does. File not found errors should be made more specific. "cant find package" "cant find message", etc)
fn loadRosMessage(
    allocator: std.mem.Allocator,
    loaded_messages: *std.StringArrayHashMap(*DataEntries),
    msg_path: []const u8,
    package_name: []const u8,
    dependencies: *const std.StringArrayHashMap([]const u8),
) LoadRosMessageError!*DataEntries {
    var msg_str: ?[]const u8 = null;

    var msg_it = std.mem.tokenizeScalar(u8, msg_path, '/');

    while (msg_it.next()) |token| {
        msg_str = token;
    }
    if (msg_str == null) {
        return LoadRosMessageError.MalformedMessageInputError;
    }

    if (msg_str.?.len <= ".msg".len) return LoadRosMessageError.MalformedMessageInputError;
    const msg_name = msg_str.?[0 .. msg_str.?.len - ".msg".len];

    var data_entries = try DataEntries.create(allocator, msg_name, package_name);
    try loaded_messages.put(data_entries.key, data_entries);

    var msg = std.fs.openFileAbsolute(msg_path, .{}) catch |err| {
        std.log.err("couldn't open file: {s}", .{msg_path});
        return err;
    };
    defer msg.close();

    const msg_data = try msg.readToEndAlloc(allocator, std.math.maxInt(usize));

    var data_it = std.mem.splitScalar(u8, msg_data, '\n');
    while (data_it.next()) |line| {
        try data_entries.addLine(allocator, loaded_messages, line, package_name, dependencies);
    }

    // Open directory using standard pattern {searchpath}/share/{package name}/msg/{message name}

    // Copy loading from main, stripping the file writting for now

    // return data entries.
    return data_entries;
}

// Search a colon separated list of directories. This should be called when building against an
// existing ROS install. It assumes that search paths has the same format as AMENT_PREFIX_PATH
// Callee is responsible for the returned memory
fn searchForPackageInShare(allocator: std.mem.Allocator, package_name: []const u8, search_paths: []const u8) ![]const u8 {
    var search_paths_it = std.mem.tokenizeScalar(u8, search_paths, ':');

    while (search_paths_it.next()) |path| {
        const share_path = try std.fmt.allocPrint(allocator, "{s}/share", .{path});
        defer allocator.free(share_path);

        var base_dir = std.fs.openDirAbsolute(share_path, .{ .iterate = true }) catch |err| switch (err) {
            error.FileNotFound => return error.CantFindShareDirInSearchPath,
            else => return err,
        };
        defer base_dir.close();
        var base_dir_it = base_dir.iterate();

        while (try base_dir_it.next()) |directory| if (std.mem.eql(u8, directory.name, package_name)) {
            return try std.fmt.allocPrint(allocator, "{s}/{s}", .{ share_path, directory.name });
        };
    }

    return error.CantFindPackageError;
}

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = if (builtin.mode == .Debug) gpa.deinit();

    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer if (builtin.mode == .Debug) arena.deinit();

    // Note all code in this program assumes an arena is used.
    // Calls to deinit that only deal with memory will be dropped.
    const allocator = arena.allocator();

    var loaded_messages = std.StringArrayHashMap(*DataEntries).init(allocator);

    const args = try std.process.argsAlloc(allocator);

    if (args.len < 4) {
        std.log.err("Incorrect number of arguments, expected at least 3", .{});
        return 1;
    }

    const package_name = args[1];
    const search_paths = args[2];
    const output_module_file = args[3];

    if (output_module_file.len > 4 and std.mem.eql(u8, output_module_file[output_module_file.len - 5 ..], ".zig")) {
        std.log.err("output module is malformed: {s} (missing suffix or empty)", .{output_module_file});
        return error.MalformedOutputModuleFile;
    }

    // TODO assert package name matches? (infer package name from output module?)
    const output_module_path = output_module_file[0 .. output_module_file.len - 5 - package_name.len];

    var dependencies = std.StringArrayHashMap([]const u8).init(allocator);

    if (args.len > 4) {
        for (args[4..]) |arg| {
            if (arg.len > 2 and std.mem.eql(u8, arg[0..2], "-D")) {
                var it = std.mem.tokenizeScalar(u8, arg[2..], ':');
                const dep_name = it.next() orelse return error.EmptyDependencyArgument;
                const dep_path = it.next() orelse {
                    std.log.err(
                        \\Malformed dependency argument, expected colon when using the generator 
                        \\in non search mode: "{s}"
                    , .{arg});
                    return error.MalformedDependencyArgument;
                };
                // Note args exists for the entire main function, so no memory handling is added.
                // If args don't live forever for some reason, we'll need to dupe and free manually
                try dependencies.put(dep_name, dep_path);
            }
        }
    }

    const input_base = if (std.mem.containsAtLeast(u8, search_paths, 1, ":"))
        try searchForPackageInShare(allocator, package_name, search_paths)
    else
        // input path only has single item, could still either be raw package (from a zig built
        // interface) or standard ros path that assumes share.
        searchForPackageInShare(allocator, package_name, search_paths) catch |err| switch (err) {
            error.CantFindShareDirInSearchPath => try allocator.dupe(u8, search_paths),
            else => return err,
        };

    // Need to put the current package in as a dependency as well for intra package dependencies later on
    try dependencies.put(package_name, input_base);

    var base_dir = try std.fs.openDirAbsolute(input_base, .{});
    defer base_dir.close();

    // Its not guarenteed that we need to create each dir
    const output_msg_dir_path = try std.fmt.allocPrint(allocator, "{s}/msg", .{output_module_path});

    std.debug.print("creating: {s}", .{output_msg_dir_path});
    std.fs.makeDirAbsolute(output_msg_dir_path) catch |err| switch (err) {
        error.PathAlreadyExists => {},
        else => return err,
    };
    var output_msg_dir = try std.fs.openDirAbsolute(output_msg_dir_path, .{});
    defer output_msg_dir.close();

    var output_module = std.ArrayList(u8).init(allocator);

    try output_module.appendSlice("pub const msg = struct {\n");
    var output_module_writer = output_module.writer();

    // This assumes that there's a msg dir
    // TODO srv and actions?
    const msg_path = try std.fmt.allocPrint(allocator, "{s}/msg", .{input_base});

    var msg_dir = try base_dir.openDir(msg_path, .{ .iterate = true });
    defer msg_dir.close();
    var msg_dir_it = msg_dir.iterate();
    while (try msg_dir_it.next()) |msg_file| {
        const msg_str = msg_file.name;
        if (msg_str.len > 3 and std.mem.eql(u8, msg_str[msg_str.len - 3 .. msg_str.len], "msg")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ msg_path, msg_file.name });

            var data_entries = try loadRosMessage(allocator, &loaded_messages, path, package_name, &dependencies);
            const zig_msg_str = try std.fmt.allocPrint(allocator, "{s}.zig", .{msg_str[0 .. msg_str.len - 4]});

            try output_module_writer.print(
                "    pub const {[msg]s} = @import(\"msg/{[msg]s}.zig\").{[msg]s};\n",
                .{ .msg = msg_str[0 .. msg_str.len - 4] },
            );

            var zig_file = try output_msg_dir.createFile(zig_msg_str, .{});
            defer zig_file.close();

            var message_meta = MessageMetadata{
                .struct_payload = try data_entries.payload(allocator),
                .msg_type = data_entries.message_name,
                .package_name = data_entries.package_name,
                .init_body = "",
                .deinit_body = "",
                .additional_imports = try data_entries.additionalImports(allocator),
            };

            if (data_entries.initRequired(&loaded_messages)) {
                message_meta.init_body = try data_entries.initFunction(allocator, &loaded_messages);
            }

            if (data_entries.deinitRequired(&loaded_messages)) {
                message_meta.deinit_body = try data_entries.deinitFunction(allocator, &loaded_messages);
            }

            const zig_file_contents = try std.fmt.allocPrint(allocator, file_format, .{
                .struct_payload = message_meta.struct_payload,
                .msg_type = message_meta.msg_type,
                .package_name = message_meta.package_name,
                .init_body = message_meta.init_body,
                .deinit_body = message_meta.deinit_body,
                .additional_imports = message_meta.additional_imports,
            });

            try zig_file.writeAll(zig_file_contents);
        }
    }

    try output_module_writer.writeAll("};\n");

    var output_file = try std.fs.createFileAbsolute(output_module_file, .{});
    defer output_file.close();

    try output_file.writeAll(output_module.items);

    return 0;
}
