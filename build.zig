const std = @import("std");
const ZigRos = @import("zigros").ZigRos;

const RclzigBuild = struct {
    const Self = @This();
    pub fn init(allocator: std.mem.Allocator, b: *std.Build) Self {
        const return_value = Self{
            .interface_generations = std.ArrayList(*std.Build.Step.Run).init(allocator),
            .modules = std.StringHashMap(*std.Build.Module).init(allocator),
            .interface_generation = b.addExecutable(.{
                .target = b.graph.host,
                .name = "interface_generation",
                .root_source_file = b.path("rclzig/message_generation.zig"),
            }),
            .rclzig_module = b.addModule(
                "rclzig",
                .{ .root_source_file = b.path("rclzig/rclzig.zig") },
            ),
            .build = b,
        };
        return return_value;
    }

    pub fn addInterface(self: *Self, package: []const u8, search_path: std.Build.LazyPath) void {
        const step = self.interface_generations.addOne() catch @panic("OOM");
        step.* = self.build.addRunArtifact(self.interface_generation);

        step.*.addArg(package);
        step.*.addDirectoryArg(search_path);
        // // TODO figure out when to free this? (arena?)
        // // TODO don't use builds allocator?
        // const zig_module_path = std.fmt.allocPrint(
        //     self.build.allocator,
        //     "{[package]s}/{[package]s}.zig",
        //     .{ .package = package },
        // ) catch @panic("OOM");

        // const interface_module_path = step.*.addOutputDirectoryArg(package);
        const interface_module_path = step.*.addOutputFileArg("builtin_interfaces.zig");

        // TODO figure out what this "package module set" buisness is and if its important to not over expose these
        const new_module = (self.modules.getOrPut(package) catch @panic("OOM")).value_ptr;
        new_module.* = self.build.addModule(
            package,
            .{
                .root_source_file = interface_module_path,
            },
        );

        new_module.*.addImport("rclzig", self.rclzig_module);
    }

    pub fn addExe(self: *Self, exe: *std.Build.Step.Compile) void {
        exe.linkLibC(); // TODO which one? figure out how to set this better (we want the option for static linking in the future)

        // TODO combile steps no longer have an "add module" option?
        exe.root_module.addImport("rclzig", self.rclzig_module);
        for (self.interface_generations.items) |interfaces| {
            exe.step.dependOn(&interfaces.step);
        }
        var module_it = self.modules.iterator();
        // var buf: [1024]u8 = undefined;
        while (module_it.next()) |entry| {
            exe.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
            // TODO presumably the following is built as a dependency now and linked separately?
            // exe.linkSystemLibrary(std.fmt.bufPrint(&buf, "{s}__rosidl_typesupport_c", .{entry.key_ptr.*}) catch @panic("OOM"));
        }
        // exe.step.dependOn(&step);
        // exe.addModule("std_msgs", std_msgs_module);
    }
    interface_generations: std.ArrayList(*std.Build.Step.Run),
    modules: std.StringHashMap(*std.Build.Module),
    build: *std.Build,
    interface_generation: *std.Build.Step.Compile,
    rclzig_module: *std.Build.Module,
};

// TODO move this somewhere generic?
pub fn linkLibraryRecursive(src: anytype, dependency: *std.Build.Step.Compile) void {
    src.linkLibrary(dependency);
    // TODO this is here to try and capture all the "header only" libraries that ros2 includes
    // that are managed via "named write files". This in theory avoids us needing to be explicit though which might be nice?
    // this does appear to work
    for (dependency.root_module.include_dirs.items) |directory| switch (directory) {
        .path => |dir| src.addIncludePath(dir),
        else => {},
    };
    for (dependency.step.dependencies.items) |dep| switch (dep.id) {
        .compile => {
            const compile: *std.Build.Step.Compile = @fieldParentPtr("step", dep);
            src.linkLibrary(compile);
            linkLibraryRecursive(src, compile);
        },
        else => {},
    };
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigros = ZigRos.init(b.dependency("zigros", .{
        .target = target,
        .optimize = optimize,
    })) orelse return;

    var ros_build = RclzigBuild.init(b.allocator, b);

    const exe = b.addExecutable(.{
        .name = "zig-node",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    if (optimize != .Debug) {
        exe.root_module.strip = true;
        exe.want_lto = true;
    }

    // TODO once / if rclzig is moved into the zigros repo this would be changed to a call on the exe only like:
    // zigros.linkRclzig(&exe.root_module);
    zigros.linkRcl(ros_build.rclzig_module);
    zigros.linkRcl(&exe.root_module);
    zigros.linkRmwCycloneDds(&exe.root_module);
    zigros.linkLoggerSpd(&exe.root_module);

    ros_build.addInterface("builtin_interfaces", zigros.ros_libraries.builtin_interfaces.share);

    // TODO should interfaces be added to specific exe? (probably)
    ros_build.addExe(exe);

    // Uncomment the following for linking the full ubsan runtimes.
    // exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/clang-18/lib/clang/18/lib/x86_64-unknown-linux-gnu" });
    // exe.linkSystemLibrary2("clang_rt.ubsan_standalone", .{ .preferred_link_mode = .static });
    // exe.linkSystemLibrary2("clang_rt.ubsan_standalone_cxx", .{ .preferred_link_mode = .static });

    b.installArtifact(exe);

    // // This allows the user to pass arguments to the application in the build
    // // command itself, like this: `zig build run -- arg1 arg2 etc`
    // if (b.args) |args| {
    //     run_cmd.addArgs(args);
    // }
}
