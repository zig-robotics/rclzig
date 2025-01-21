const std = @import("std");
const builtin = @import("builtin");

pub const std_options = .{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

const rclzig = @import("rclzig");

const rosidl_runtime = rclzig.rosid_runtime;

const builtin_interfaces = @import("builtin_interfaces");

pub var my_pub: rclzig.publisher.Publisher(builtin_interfaces.msg.Time) = undefined;
pub var pub_msg = builtin_interfaces.msg.Time{};
pub var short_timer_counter: i32 = 0;

pub fn mySubscriberCallback(msg: builtin_interfaces.msg.Time) !void {
    // pub fn mySubscriberCallback(msg: std_msgs.msg.Int32) !void {
    std.log.info("Callback: I heard: {}", .{msg.sec});
}

pub fn myTimerCallback() !void {
    try my_pub.publish(pub_msg);
    pub_msg.sec += 1;
}

pub fn shortTimerCallback() void {
    std.log.info("shorttimer {}", .{blk: {
        const ref = &short_timer_counter;
        const tmp = ref.*;
        ref.* +%= 1;
        break :blk tmp;
    }});
}

// const TestNode = struct {
//     publisher: rclzig.publisher.Publisher(builtin_interfaces.msg.Time),
//     subscription: rclzig.subscription.Subscription(builtin_interfaces.msg.Time),
//     timer: rclzig.Timer,
//     last_sec: i32 = 0,

//     fn subCallback(self: TestNode, msg: builtin_interfaces.msg.Time) !void {
//         self.last_sec = msg.sec;
//         std.log.info("subscriber callback, current time {}, prev time {}", .{ msg.sec, self.last_sec });
//     }
// };

pub fn main() !u8 {
    var gpa = std.heap.GeneralPurposeAllocator(.{ .enable_memory_limit = true }){};
    defer {
        const deinit_status = gpa.deinit();
        if (deinit_status == .leak) {
            std.log.err("Memory was leaked!", .{});
        } else {
            std.log.debug("general purpose allocator reports no leaks", .{});
        }
    }
    var allocator = gpa.allocator();

    // var allocator = std.heap.c_allocator; // The subscriber middleware seems to be calling free internally.
    // This means that when sequences are used, we're forced to use the c allocator

    // var buffer: [4000]u8 = undefined;
    // var fba = std.heap.FixedBufferAllocator.init(&buffer);
    // var allocator = fba.allocator();

    var context = try rclzig.init(&allocator);
    defer rclzig.shutdown(&context);

    var clock = try rclzig.time.Clock.init(&allocator, rclzig.time.ClockType.system_time);
    defer clock.deinit();

    // Does context and node options need to be a pointer here?
    var my_node = try rclzig.Node.init(&allocator, "name_0", &context);
    defer my_node.deinit();

    const topic_name_zig: [:0]const u8 = "topic_0";

    my_pub = try rclzig.publisher.Publisher(builtin_interfaces.msg.Time).init(
        &std.heap.c_allocator,
        &my_node,
        topic_name_zig,
        rclzig.rmw.QosProfile{ .depth = 1 },
    );
    defer my_pub.deinit(&my_node) catch {};

    var my_timer = try rclzig.Timer.init(&allocator, .{ .callback_with_error = &myTimerCallback }, &clock, &context, 1000 * std.time.ns_per_ms);
    defer my_timer.deinit();

    var short_timer = try rclzig.Timer.init(&allocator, .{ .callback = &shortTimerCallback }, &clock, &context, 100 * std.time.ns_per_ms);
    defer short_timer.deinit();

    pub_msg.sec = 1;

    var my_zig_sub = try rclzig.subscription.Subscription(builtin_interfaces.msg.Time).init(
        &std.heap.c_allocator,
        &my_node,
        &mySubscriberCallback,
        topic_name_zig,
        rclzig.rmw.QosProfile{},
    );
    defer my_zig_sub.deinit(std.heap.c_allocator);

    var executor = try rclzig.Executor.init(allocator);
    defer executor.deinit();

    try executor.addSubscription(&my_zig_sub);
    try executor.addTimer(&my_timer);
    try executor.addTimer(&short_timer);
    try executor.spin(&allocator, &context);

    std.log.info("shuhtting down...", .{});
    return 0;
}
