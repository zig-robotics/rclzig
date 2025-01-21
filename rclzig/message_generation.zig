const std = @import("std");

const sequence = @import("sequence.zig");
const file_format =
    \\const std = @import("std");
    \\const rosidl_runtime = @import("rclzig").rosidl_runtime;
    \\{[additional_imports]s}
    \\// TODO this returns a c pointer, does this allocate? UPDATE it seems to actually be a pointer to some global fuckery in the shared library so no, this does not allocate?
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
                // TODO consider error if complex type is empty?
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
                bounded_string, // TODO bounded strings? The way bounded strings work they'd be better off as a base type?
            };

            kind: Kind,
            size: usize,
        };

        data_type: Type,
        array_type: ?ArrayType,
        is_constant: bool,
        name: []u8,
        // TODO should default be optional? right now we zero everything but that's not very "ziggy"
        default: []u8,
    };

    pub fn init(self: *Self, allocator: std.mem.Allocator, message_name: []const u8, package_name: []const u8) !void {
        self.arena = std.heap.ArenaAllocator.init(allocator);
        self.entries = std.ArrayList(Entry).init(self.arena.allocator());
        self.dependencies = std.StringHashMap(Self).init(self.arena.allocator());
        self.message_name = try std.fmt.allocPrint(self.arena.allocator(), "{s}", .{message_name});
        self.package_name = try std.fmt.allocPrint(self.arena.allocator(), "{s}", .{package_name});
    }
    pub fn deinit(self: *Self) void {
        self.arena.deinit();
    }

    pub fn addEntry(self: *Self, data_type: Entry.Type, array_type_in: ?Entry.ArrayType, is_constant: bool, name: []const u8, default_in: ?[]const u8) !void {
        var new_entry = try self.entries.addOne();
        new_entry.data_type = data_type;
        new_entry.array_type = array_type_in;
        new_entry.is_constant = is_constant;
        new_entry.name = try self.arena.allocator().alloc(u8, name.len);
        @memcpy(new_entry.name, name);

        if (default_in) |default| {
            new_entry.default = try self.arena.allocator().alloc(u8, default.len);
            @memcpy(new_entry.default, default);
        } else {
            if (array_type_in) |array_type| switch (array_type.kind) {
                .static_array => {
                    var result = std.ArrayList(u8).init(self.arena.allocator());
                    try result.appendSlice("[ ");
                    for (0..array_type.size) |_| {
                        switch (data_type) {
                            .complex_type => try result.appendSlice(".{}, "),
                            .base_type => |base_type| switch (base_type.zigType()) {
                                .bool => try result.appendSlice("false, "),
                                .RosString => try result.appendSlice(".{}, "),
                                else => try result.appendSlice("0, "),
                            },
                        }
                    }
                    try result.appendSlice("]");
                    new_entry.default = result.items;
                },
                .unbounded_dynamic_array => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "", .{}),
                .bounded_dynamic_array => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "", .{}),
                .bounded_string => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "TODO", .{}),
            } else switch (data_type) {
                .base_type => |base_type| switch (base_type.zigType()) {
                    .bool => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "false", .{}),
                    .RosString => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "", .{}),
                    else => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), "0", .{}),
                },
                .complex_type => new_entry.default = try std.fmt.allocPrint(self.arena.allocator(), ".{{}}", .{}),
            }
        }
    }

    pub fn additionalImports(self: *Self) ![]u8 {
        var buffer = std.ArrayList(u8).init(self.arena.allocator());
        try buffer.resize(128);
        var result = std.ArrayList(u8).init(self.arena.allocator());
        var writer = result.writer();
        var imports = std.StringHashMap(void).init(self.arena.allocator());
        for (self.entries.items) |entry| {
            if (entry.array_type) |array_type| {
                switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array, .bounded_string => {
                        const SEQUENCE_IMPORT = "const Sequence = @import(\"rclzig\").Sequence;\n";
                        if (!imports.contains(SEQUENCE_IMPORT)) {
                            try imports.put(SEQUENCE_IMPORT, void{});
                            try writer.writeAll(SEQUENCE_IMPORT);
                        }
                    },
                    .static_array => {},
                }
            }
            switch (entry.data_type) {
                .complex_type => |data_type| {
                    var package_it = std.mem.tokenizeAny(u8, data_type, ".");
                    const package = package_it.next().?;
                    if (!imports.contains(package)) {
                        try imports.put(package, void{});
                        try writer.print("const {[package]s} = @import(\"{[package]s}\");\n", .{ .package = package });
                    }
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        const STRING_IMPORT = "const RosString = @import(\"rclzig\").RosString;\n";
                        if (!imports.contains(STRING_IMPORT)) {
                            try imports.put(STRING_IMPORT, void{});
                            try writer.writeAll(STRING_IMPORT);
                        }
                    },
                    else => {},
                },
            }
        }
        return result.items;
    }

    pub fn payload(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.arena.allocator());
        var writer = result.writer();
        for (self.entries.items) |entry| {
            if (entry.is_constant) {
                // TODO are const arrays allowed in ROS messages? NO
                // TODO switch to list of entries and list of const entires to remove double loop and if
                // Note that constants cannot be complex types, this includes dynamic arrays (bounded or unbounded), this also includes static arrays for some reason
                // Note that strings can be const, and get type
                // TODO CONST STRINGS, the have type ex:
                // static const char * const example_interfaces__msg__MyMessage__MY_CONST_STRING = "asdf";
                try writer.print("    const {s}: {s} = {s};\n", .{ entry.name, @tagName(entry.data_type.base_type.zigType()), entry.default });
            }
        }
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                try writer.print("    {s}: ", .{entry.name});
                if (entry.array_type) |array_type| {
                    switch (array_type.kind) {
                        .unbounded_dynamic_array => {
                            try writer.print("Sequence({s}, null) = .{{}},\n", .{entry.data_type.name()});
                        },
                        .bounded_dynamic_array => {
                            try writer.print("Sequence({s}, {}) = .{{}},\n", .{ entry.data_type.name(), array_type.size });
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
                        else => unreachable, // TODO random string array type?
                    }
                } else switch (entry.data_type) {
                    .base_type => |data_type| switch (data_type) {
                        .string => try writer.print("{s} = .{{}},\n", .{entry.data_type.name()}),
                        else => try writer.print("{s} = {s},\n", .{ entry.data_type.name(), entry.default }),
                    },
                    else => try writer.print("{s} = {s},\n", .{ entry.data_type.name(), entry.default }),
                }
            }
        }
        return result.items;
    }

    pub fn initFunction(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.arena.allocator());
        var writer = result.writer();

        try writer.writeAll("    pub fn init(allocator: std.mem.Allocator) !Self {\n");
        try writer.writeAll("        var return_value: Self = .{};\n");

        for (self.entries.items) |entry| if (!entry.is_constant) {
            if (entry.array_type) |array_type| switch (array_type.kind) {
                .static_array => switch (entry.data_type) {
                    .complex_type => |data_type| if (self.dependencies.get(data_type).?.initRequired()) {
                        // TODO get rid of question mark opperator
                        try writer.print("        for(return_value.{s}) |*entry| entry.init(allocator);\n", .{entry.name});
                    },
                    .base_type => |data_type| switch (data_type.zigType()) {
                        .RosString => try writer.print("        for(return_value.{s}) |*entry| entry.init(allocator);\n", .{entry.name}),
                        else => {},
                    },
                }, // TODO should complex array types be default initialized? I think so? this covers the edge case of default dynamic arrays? Check what C does later
                .unbounded_dynamic_array, .bounded_dynamic_array => {
                    var token_it = std.mem.tokenizeAny(u8, entry.default, "[ ,]");
                    while (token_it.next()) |token| {
                        try writer.print("        return_value.{s}.append(allocator, {s});\n", .{ entry.name, token });
                    }
                },
                .bounded_string => {}, // TODO bounded strings
            } else switch (entry.data_type) {
                .complex_type => |data_type| {
                    if (self.dependencies.get(data_type).?.initRequired()) {
                        // TODO get rid of question mark opperator
                        try writer.print("        return_value.{s}.init(allocator);\n", .{entry.name});
                    }
                },
                .base_type => |data_type| switch (data_type.zigType()) {
                    .RosString => {
                        try writer.print("        return_value.{s}.init(allocator);\n", .{entry.name});
                        if (entry.default.len > 0) {
                            try writer.print("        return_value.{s}.assign(allocator, {s});\n", .{ entry.name, entry.default });
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

    pub fn deinitFunction(self: *Self) ![]u8 {
        var result = std.ArrayList(u8).init(self.arena.allocator());
        var writer = result.writer();

        try writer.writeAll("    pub fn deinit(self: *Self, allocator: std.mem.Allocator) void {\n");
        for (self.entries.items) |entry| if (!entry.is_constant) {
            if (entry.array_type) |array_type| switch (array_type.kind) {
                .static_array => {
                    switch (entry.data_type) {
                        .complex_type => |data_type| {
                            if (self.dependencies.get(data_type).?.deinitRequired()) {
                                // TODO get rid of question mark opperator
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
                .complex_type => |data_type| if (self.dependencies.get(data_type).?.deinitRequired()) {
                    // TODO get rid of question mark opperator
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

    fn dependencyRequiresInit(self: Self) bool {
        var dependencies_it = self.dependencies.iterator();
        while (dependencies_it.next()) |dependency| {
            if (dependency.value_ptr.initRequired()) return true;
        }
        return false;
    }

    fn dependencyRequiresDeinit(self: Self) bool {
        var dependencies_it = self.dependencies.iterator();
        while (dependencies_it.next()) |dependency| {
            if (dependency.value_ptr.deinitRequired()) return true;
        }
        return false;
    }

    // TODO not all complex types need to be initted. Really only types with dynamic defaults need to be initted
    // Note however that any complex type that has dynamic arrays need to be deinited.
    // TODO create a separate deinit required function
    // TODO scan ahead for dependencies and check if they need init / deinit
    // DO this by building this DataEntries type for dependencies and reusing these checks?
    // On one hand this saves us from doing dynamic imports, on the other hand it feels very wasteful
    pub fn initRequired(self: Self) bool {
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                if (entry.array_type) |array_type| switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array => {
                        if (entry.default.len != 0) return true;
                    }, // TODO add bounded string?
                    else => {},
                } else {
                    switch (entry.data_type) {
                        .complex_type => |data_type| {
                            if (self.dependencies.get(data_type).?.initRequired()) return true; // TODO remove question mark oporator, handle edge case
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

    pub fn deinitRequired(self: Self) bool {
        for (self.entries.items) |entry| {
            if (!entry.is_constant) {
                switch (entry.data_type) {
                    .complex_type => |data_type| if (self.dependencies.get(data_type).?.deinitRequired()) return true, // TODO remove question mark oporator, handle edge case
                    .base_type => |data_type| switch (data_type.zigType()) {
                        .RosString => return true,
                        else => {},
                    },
                }
                if (entry.array_type) |array_type| switch (array_type.kind) {
                    .unbounded_dynamic_array, .bounded_dynamic_array => return true, // TODO add string arrays
                    else => {},
                };
            }
        }
        return false;
    }

    pub fn addLine(
        self: *Self,
        line: []const u8,
        source_package: []const u8,
        dependencies: std.StringArrayHashMap([]const u8),
    ) !void {
        var line_it = std.mem.tokenizeAny(u8, line, " "); // TODO we can't tokenize on = because its used to declare bounded arrays
        const data_type_optional = line_it.next();
        var data_type_str: []const u8 = undefined;
        if (data_type_optional) |data_type_real| {
            data_type_str = data_type_real;
        } else {
            return; // TODO error? (This one isn't really an error)
        }
        var new_type_optional: ?DataEntries.Entry.BaseType = null;

        if (std.mem.startsWith(u8, data_type_str, "#")) {
            return;
        }

        inline for (@typeInfo(DataEntries.Entry.BaseType).Enum.fields) |field| {
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
            } else { // TODO this catches the case where there's more than one /, which I'm fairly sure is an error
                package = source_package;
                var it = std.mem.tokenizeAny(u8, data_type_str, "/[]"); // tokenizing on square brackets as lazy way to remove any array marker
                msg = it.next().?;
            }

            new_type = .{ .complex_type = try std.fmt.allocPrint(self.arena.allocator(), "{s}.msg.{s}", .{ package, msg }) };
            const new_type_path = try std.fmt.allocPrint(
                self.arena.allocator(),
                "{s}/msg/{s}",
                .{ dependencies.get(package) orelse {
                    std.log.err(
                        "Generating message {s} requires dependency {s}, but that dependency was not found",
                        .{ self.message_name, package },
                    );
                    return LoadRosMessageError.CantFindPackageError;
                }, msg },
            );
            const loaded_message = loadRosMessage(self.arena.allocator(), new_type_path, package, dependencies) catch |err| switch (err) {
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
                else => return err,
            };
            try self.dependencies.put(new_type.complex_type, loaded_message);
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
                    // TODO there is the random string array type??
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
                    // TODO need another itterator since now we don't want to tokenize on white space
                    var value_it = std.mem.tokenizeAny(u8, name_it.buffer[name_it.index - value.len .. name_it.buffer.len], "[]#");
                    new_value = value_it.next();
                    // TODO handle value, this could be either a default or a constant or a comment
                }
            } else if (new_is_constant) {
                // TODO Constants must have a value, this is an error
            }
            try self.addEntry(new_type, new_array_type, new_is_constant, new_name, new_value);
        }
    }
    arena: std.heap.ArenaAllocator = undefined,
    entries: std.ArrayList(Entry) = undefined,
    dependencies: std.StringHashMap(Self) = undefined,
    message_name: []const u8 = undefined,
    package_name: []const u8 = undefined,
};

pub fn isUppercase(string: []const u8) bool {
    for (string) |character| {
        if (std.ascii.isAlphabetic(character) and std.ascii.isLower(character)) {
            return false;
        }
    }
    return true;
}

const Derp = struct {
    a: i8 = 0,
};

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
    msg_path: []const u8,
    package_name: []const u8,
    dependencies: std.StringArrayHashMap([]const u8),
) LoadRosMessageError!DataEntries {
    var msg_str: ?[]const u8 = null;

    var msg_it = std.mem.tokenizeAny(u8, msg_path, "/");

    while (msg_it.next()) |token| {
        msg_str = token;
    }
    if (msg_str == null) {
        return LoadRosMessageError.MalformedMessageInputError;
    }

    if (msg_str.?.len <= ".msg".len) return LoadRosMessageError.MalformedMessageInputError;
    const msg_name = msg_str.?[0 .. msg_str.?.len - ".msg".len];

    var data_entries = DataEntries{ .arena = undefined, .entries = undefined, .dependencies = undefined };
    try data_entries.init(allocator, msg_name, package_name);
    errdefer data_entries.deinit();

    // TODO look at example inits for better API
    // Ideally data_entries = DataEntries.init(allocator)

    var msg = try std.fs.openFileAbsolute(msg_path, .{});
    defer msg.close();

    const msg_data = try msg.readToEndAlloc(allocator, std.math.maxInt(usize));
    defer allocator.free(msg_data);

    var data_it = std.mem.split(u8, msg_data, "\n");
    while (data_it.next()) |line| {
        try data_entries.addLine(line, package_name, dependencies);
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
    var search_paths_it = std.mem.tokenizeAny(u8, search_paths, ":");

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
    defer _ = gpa.deinit();

    const allocator = gpa.allocator();

    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);

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
    defer dependencies.deinit();

    if (args.len > 4) {
        for (args[4..]) |arg| {
            if (arg.len > 2 and std.mem.eql(u8, arg[0..2], "-D")) {
                var it = std.mem.tokenizeAny(u8, arg[2..], "-D");
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

    var input_base: []const u8 = undefined;
    defer allocator.free(input_base);

    if (std.mem.containsAtLeast(u8, search_paths, 1, ":")) {
        input_base = try searchForPackageInShare(allocator, package_name, search_paths);
    } else {
        // input path only has single item, could still either be raw package (from a zig built
        // interface) or standard ros path that assumes share.
        input_base = searchForPackageInShare(allocator, package_name, search_paths) catch |err| switch (err) {
            error.CantFindShareDirInSearchPath => try allocator.dupe(u8, search_paths),
            else => return err,
        };
    }

    var base_dir = try std.fs.openDirAbsolute(input_base, .{});
    defer base_dir.close();

    // TODO we should accumulate a list of interface types (msg, srv, actions)
    // Its not guarenteed that we need to create each dir
    const output_msg_dir_path = try std.fmt.allocPrint(allocator, "{s}/msg", .{output_module_path});
    defer allocator.free(output_msg_dir_path);

    try std.fs.makeDirAbsolute(output_msg_dir_path);
    var output_msg_dir = try std.fs.openDirAbsolute(output_msg_dir_path, .{});
    defer output_msg_dir.close();

    var output_module = std.ArrayList(u8).init(allocator);
    defer output_module.deinit();

    try output_module.appendSlice("pub const msg = struct {\n");
    var output_module_writer = output_module.writer();

    // This assumes that there's a msg dir
    // TODO srv and actions?
    const msg_path = try std.fmt.allocPrint(allocator, "{s}/msg", .{input_base});
    defer allocator.free(msg_path);

    var msg_dir = try base_dir.openDir(msg_path, .{ .iterate = true });
    defer msg_dir.close();
    var msg_dir_it = msg_dir.iterate();
    while (try msg_dir_it.next()) |msg_file| {
        const msg_str = msg_file.name;
        if (msg_str.len > 3 and std.mem.eql(u8, msg_str[msg_str.len - 3 .. msg_str.len], "msg")) {
            const path = try std.fmt.allocPrint(allocator, "{s}/{s}", .{ msg_path, msg_file.name });
            defer allocator.free(path);

            var data_entries = try loadRosMessage(allocator, path, package_name, dependencies);
            defer data_entries.deinit();
            const zig_msg_str = try std.fmt.allocPrint(allocator, "{s}.zig", .{msg_str[0 .. msg_str.len - 4]});
            defer allocator.free(zig_msg_str);

            try output_module_writer.print(
                "    pub const {[msg]s} = @import(\"msg/{[msg]s}.zig\").{[msg]s};\n",
                .{ .msg = msg_str[0 .. msg_str.len - 4] },
            );

            var zig_file = try output_msg_dir.createFile(zig_msg_str, .{});
            defer zig_file.close();

            var data_payload = std.ArrayList(u8).init(allocator);
            defer data_payload.deinit();

            var message_meta = MessageMetadata{
                .struct_payload = try data_entries.payload(),
                .msg_type = data_entries.message_name,
                .package_name = data_entries.package_name,
                .init_body = "",
                .deinit_body = "",
                .additional_imports = try data_entries.additionalImports(),
            };

            if (data_entries.initRequired()) {
                message_meta.init_body = try data_entries.initFunction();
            }

            if (data_entries.deinitRequired()) {
                message_meta.deinit_body = try data_entries.deinitFunction();
            }

            const zig_file_contents = try std.fmt.allocPrint(allocator, file_format, .{
                .struct_payload = message_meta.struct_payload,
                .msg_type = message_meta.msg_type,
                .package_name = message_meta.package_name,
                .init_body = message_meta.init_body,
                .deinit_body = message_meta.deinit_body,
                .additional_imports = message_meta.additional_imports,
            });
            defer allocator.free(zig_file_contents);

            try zig_file.writeAll(zig_file_contents);
        }
    }

    try output_module_writer.writeAll("};\n");

    var output_file = try std.fs.createFileAbsolute(output_module_file, .{});
    defer output_file.close();

    try output_file.writeAll(output_module.items);

    return 0;
}

// test "simple test" {
//     var out_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
//     const directory_to_search = try std.fs.realpath("std_msgs", &out_buffer);
//     const dirs = try std.fs.openDirAbsolute(directory_to_search, .{});

//     std.log.info("dirs: {}", .{dirs});

//     const file = try std.fs.cwd().createFile(
//         "junk_file.txt\n",
//         .{ .read = true },
//     );
//     defer file.close();

//     const bytes_written = try file.writeAll("Hello File!");
//     _ = bytes_written;
// }
