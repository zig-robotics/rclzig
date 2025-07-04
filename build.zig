const std = @import("std");
const ZigRos = @import("zigros").ZigRos;

pub const RclzigBuild = struct {
    pub const RosBuild = union(enum) {
        zigros: *const ZigRos,
        system: void, // TODO add back system ROS option
    };

    const Self = @This();
    interface_generations: std.ArrayList(*std.Build.Step.Run),
    modules: std.StringHashMap(*std.Build.Module),
    build: *std.Build,
    interface_generation: *std.Build.Step.Compile,
    rclzig_module: *std.Build.Module,

    pub fn init(allocator: std.mem.Allocator, b: *std.Build, ros_build: RosBuild) Self {
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
        switch (ros_build) {
            .zigros => |zigros| {
                zigros.linkRcl(return_value.rclzig_module);
                zigros.linkRmwCycloneDds(return_value.rclzig_module); // TODO make RMW selectable?
                zigros.linkLoggerSpd(return_value.rclzig_module); // TODO make logger selectable
            },
            .system => @panic("System installs of ROS are not currently supported, please use zigros for now"),
        }
        return return_value;
    }

    pub const Dependency = struct {
        name: []const u8,
        path: std.Build.LazyPath,
    };

    pub fn addInterface(self: *Self, package: []const u8, search_path: std.Build.LazyPath, dependencies: []const Self.Dependency) void {
        const step = self.interface_generations.addOne() catch @panic("OOM");
        step.* = self.build.addRunArtifact(self.interface_generation);

        step.*.addArg(package);
        step.*.addDirectoryArg(search_path);

        const zig_module_path = std.fmt.allocPrint(
            self.build.allocator,
            "{[package]s}.zig",
            .{ .package = package },
        ) catch @panic("OOM");

        // const interface_module_path = step.*.addOutputDirectoryArg(package);
        const interface_module_path = step.*.addOutputFileArg(zig_module_path);

        const new_module = (self.modules.getOrPut(package) catch @panic("OOM")).value_ptr;
        new_module.* = self.build.addModule(
            package,
            .{
                .root_source_file = interface_module_path,
            },
        );
        // Add itself as a module to cover the case of inter package dependencies
        new_module.*.addImport(package, new_module.*);
        for (dependencies) |dep| {
            const name = std.fmt.allocPrint(self.build.allocator, "-D{s}:", .{dep.name}) catch @panic("OOM");
            // builds are transient, let it leak who cares
            step.*.addPrefixedDirectoryArg(name, dep.path);
            new_module.*.addImport(dep.name, self.modules.get(dep.name) orelse {
                const error_msg = std.fmt.allocPrint(
                    self.build.allocator,
                    "Error, dependency not found: {s}, please add all required dependencies in order. Resolving out of order dependencies isn't supported for now.",
                    .{dep.name},
                ) catch "Error, dependency not found.";
                @panic(error_msg);
            });
        }

        new_module.*.addImport("rclzig", self.rclzig_module);
    }

    pub fn addExe(self: *Self, exe: *std.Build.Step.Compile) void {
        exe.linkLibC();

        exe.root_module.addImport("rclzig", self.rclzig_module);
        for (self.interface_generations.items) |interfaces| {
            exe.step.dependOn(&interfaces.step);
        }
        var module_it = self.modules.iterator();
        // var buf: [1024]u8 = undefined;
        while (module_it.next()) |entry| {
            exe.root_module.addImport(entry.key_ptr.*, entry.value_ptr.*);
        }
    }
};

// Helper function for setting up tests that start a full fledged ROS system for their tests
fn addRosTest(
    b: *std.Build,
    root_source_file: std.Build.LazyPath,
    target: ?std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    ros_build: *RclzigBuild,
    test_ros_step: *std.Build.Step,
    coverage: bool,
) *std.Build.Step.Compile {
    const ros_test = b.addTest(.{
        .root_source_file = root_source_file,
        .target = target,
        .optimize = optimize, // TODO should this be debug always?
    });

    ros_build.addExe(ros_test);

    ros_test.linkLibC();
    test_ros_step.dependOn(&b.addRunArtifact(ros_test).step);

    if (coverage) {
        // TODO this introduces a system dependency on kcov, add option to build kcov?
        ros_test.setExecCmd(&.{
            "kcov",
            "kcov-output",
            null,
        });
    }
    return ros_test;
}

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const zigros = ZigRos.init(b.dependency("zigros", .{
        .target = target,
        .optimize = optimize,
    })) orelse return;

    var ros_build = RclzigBuild.init(b.allocator, b, .{ .zigros = &zigros });

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

    ros_build.addInterface("builtin_interfaces", zigros.ros_libraries.builtin_interfaces.share, &.{});
    ros_build.addInterface(
        "rcl_interfaces",
        zigros.ros_libraries.rcl_interfaces.share,
        &.{.{ .name = "builtin_interfaces", .path = zigros.ros_libraries.builtin_interfaces.share }},
    );

    ros_build.addExe(exe);

    // Uncomment the following for linking the full ubsan runtimes.
    // exe.addLibraryPath(std.Build.LazyPath{ .cwd_relative = "/clang-18/lib/clang/18/lib/x86_64-unknown-linux-gnu" });
    // exe.linkSystemLibrary2("clang_rt.ubsan_standalone", .{ .preferred_link_mode = .static });
    // exe.linkSystemLibrary2("clang_rt.ubsan_standalone_cxx", .{ .preferred_link_mode = .static });

    const test_step = b.step("test", "Run unit tests that don't require initiating ROS");
    const test_ros_step = b.step("test-ros", "Run unit tests that require starting ROS. These will be slower and results may be impacted by the network.");
    const coverage = b.option(bool, "test-coverage", "Generate test coverage") orelse false;

    const string_tests = b.addTest(.{
        .root_source_file = b.path("rclzig/string.zig"),
        .target = target,
        .optimize = optimize, // TODO should this be debug always?
    });
    string_tests.linkLibC();
    zigros.linkRcl(string_tests.root_module);

    if (coverage) {
        string_tests.setExecCmd(&.{
            "kcov",
            "kcov-output",
            null,
        });
    }
    test_step.dependOn(&b.addRunArtifact(string_tests).step);

    const sequence_tests = b.addTest(.{
        .root_source_file = b.path("rclzig/sequence.zig"),
        .target = target,
        .optimize = optimize, // TODO should this be debug always?
    });
    sequence_tests.linkLibC();
    zigros.linkRcl(sequence_tests.root_module);

    if (coverage) {
        sequence_tests.setExecCmd(&.{
            "kcov",
            "kcov-output",
            null,
        });
    }

    test_step.dependOn(&b.addRunArtifact(sequence_tests).step);

    const rmw_tests = b.addTest(.{
        .root_source_file = b.path("rclzig/rmw.zig"),
        .target = target,
        .optimize = optimize, // TODO should this be debug always?
    });
    rmw_tests.linkLibC();
    zigros.linkRcl(rmw_tests.root_module);
    test_step.dependOn(&b.addRunArtifact(rmw_tests).step);

    if (coverage) {
        rmw_tests.setExecCmd(&.{
            "kcov",
            "kcov-output",
            null,
        });
    }

    const service_tests = b.addTest(.{
        .root_source_file = b.path("rclzig/service.zig"),
        .target = target,
        .optimize = optimize, // TODO should this be debug always?
    });
    zigros.linkRcl(service_tests.root_module);
    test_step.dependOn(&b.addRunArtifact(service_tests).step);

    if (coverage) {
        service_tests.setExecCmd(&.{
            "kcov",
            "kcov-output",
            null,
        });
    }

    _ = addRosTest(b, b.path("tests/service.zig"), target, optimize, &ros_build, test_ros_step, coverage);
    _ = addRosTest(b, b.path("tests/client.zig"), target, optimize, &ros_build, test_ros_step, coverage);
    _ = addRosTest(b, b.path("tests/request_response.zig"), target, optimize, &ros_build, test_ros_step, coverage);
    _ = addRosTest(b, b.path("tests/pub_sub.zig"), target, optimize, &ros_build, test_ros_step, coverage);

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the test app");
    run_step.dependOn(&run_cmd.step);
}
