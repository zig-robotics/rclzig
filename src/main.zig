const std = @import("std");
const builtin = @import("builtin");

pub const std_options = std.Options{
    .log_level = switch (builtin.mode) {
        .Debug => .debug,
        else => .info,
    },
};

const rclzig = @import("rclzig");
const builtin_interfaces = @import("builtin_interfaces");
const rcl_interfaces = @import("rcl_interfaces");

const TestNodeStrings = struct {
    const Self = @This();
    node: rclzig.Node,
    publisher: rclzig.publisher.Publisher(rcl_interfaces.msg.Log),
    subscription: rclzig.subscription.Subscription(rcl_interfaces.msg.Log, subCallback),
    timer: rclzig.Timer(timerCallback),
    log_msg: rcl_interfaces.msg.Log,
    allocator: rclzig.RclAllocator,

    fn init(
        self: *Self,
        allocator: rclzig.RclAllocator,
        clock: *rclzig.time.Clock,
        context: *rclzig.Context,
    ) !void {
        // Get defaults and mark defered initialized elements explicitly
        self.* = .{
            .node = undefined,
            .publisher = undefined,
            .subscription = undefined,
            .timer = undefined,
            .log_msg = try rcl_interfaces.msg.Log.init(allocator),
            .allocator = allocator,
        };
        errdefer self.log_msg.deinit(allocator);

        try self.log_msg.msg.assign(allocator, "boop" ** 1000000);

        self.node = try rclzig.Node.init(allocator, "test_node2", context);
        errdefer self.node.deinit();

        self.publisher = try rclzig.publisher.Publisher(rcl_interfaces.msg.Log).init(
            allocator,
            &self.node,
            "test_log",
            rclzig.rmw.QosProfile{},
        );
        errdefer self.publisher.deinit(&self.node) catch {};

        self.subscription = try rclzig.subscription.Subscription(rcl_interfaces.msg.Log, subCallback).initBind(
            allocator,
            &self.node,
            "test_log",
            rclzig.rmw.QosProfile{},
            self,
        );
        errdefer self.subscription.deinit(allocator, &self.node);

        self.timer = try rclzig.Timer(timerCallback).init(
            allocator,
            clock,
            context,
            1000000000,
            self,
        );

        self.subCallback(&self.subscription.msg);
    }

    pub fn deinit(self: *Self, allocator: rclzig.RclAllocator) void {
        self.timer.deinit();
        self.publisher.deinit(&self.node) catch {};
        self.subscription.deinit(allocator, &self.node);
        self.node.deinit();
        self.log_msg.deinit(allocator);
    }

    fn subCallback(self: *Self, msg: *const rcl_interfaces.msg.Log) void {
        _ = self;
        std.log.info(
            "subscriber callback\nmessage location: {*}\npointer location: {*}\nsize: {}\ncapacity: {}",
            .{ msg, msg.msg.data, msg.msg.size, msg.msg.capacity },
        );
    }

    fn timerCallback(self: *Self) void {
        self.publisher.publish(&self.log_msg) catch {};
        self.log_msg.msg.appendSlice(self.allocator, "bop" ** 1000000) catch @panic("OOM");
    }
};

const TestNodeSequences = struct {
    const Self = @This();
    node: rclzig.Node,
    publisher: rclzig.publisher.Publisher(rcl_interfaces.msg.ParameterValue),
    subscription: rclzig.subscription.Subscription(rcl_interfaces.msg.ParameterValue, subCallback),
    timer: rclzig.Timer(timerCallback),
    msg: rcl_interfaces.msg.ParameterValue,
    allocator: std.mem.Allocator,

    // In this node the rcl_allocator is used only for the subscriber
    // Note that a pointer to the internally stored allocator is used. Therefore
    // this object can't be trivially coppied after initialization
    fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        rcl_allocator: rclzig.RclAllocator,
        clock: *rclzig.time.Clock,
        context: *rclzig.Context,
    ) !void {
        // Get defaults and mark defered initialized elements explicitly
        self.* = .{
            .node = undefined,
            .publisher = undefined,
            .subscription = undefined,
            .timer = undefined,
            .msg = try rcl_interfaces.msg.ParameterValue.init(allocator),
            .allocator = allocator,
        };
        errdefer self.msg.deinit(allocator);

        try self.msg.integer_array_value.reserve(allocator, 1000);

        self.node = try rclzig.Node.init(rclzig.RclAllocator.initFromZig(&self.allocator), "test_node_sequence", context);
        errdefer self.node.deinit();

        self.publisher = try rclzig.publisher.Publisher(rcl_interfaces.msg.ParameterValue).init(
            rclzig.RclAllocator.initFromZig(&self.allocator),
            &self.node,
            "test_sequence",
            rclzig.rmw.QosProfile{},
        );
        errdefer self.publisher.deinit(&self.node) catch {};

        self.subscription = try rclzig.subscription.Subscription(rcl_interfaces.msg.ParameterValue, subCallback).initBind(
            rcl_allocator,
            &self.node,
            "test_sequence",
            rclzig.rmw.QosProfile{},
            self,
        );
        errdefer self.subscription.deinit(rcl_allocator, &self.node);

        self.timer = try rclzig.Timer(timerCallback).init(
            rclzig.RclAllocator.initFromZig(&self.allocator),
            clock,
            context,
            1000000000,
            self,
        );
    }

    pub fn deinit(self: *Self, rcl_allocator: rclzig.RclAllocator) void {
        self.timer.deinit();
        self.publisher.deinit(&self.node) catch {};
        self.subscription.deinit(rcl_allocator, &self.node);
        self.node.deinit();
        self.msg.deinit(self.allocator);
    }

    fn subCallback(self: *Self, msg: *const rcl_interfaces.msg.ParameterValue) void {
        _ = self;
        std.log.info(
            "sequence callback\nmessage location: {*}\npointer location: {*}\nsize: {}\ncapacity: {}",
            .{
                msg,
                msg.integer_array_value.data,
                msg.integer_array_value.size,
                msg.integer_array_value.capacity,
            },
        );
    }

    fn timerCallback(self: *Self) void {
        var array = self.msg.integer_array_value.toArrayList();
        array.appendSlice(self.allocator, &[_]i64{10} ** 1000000) catch @panic("OOM");

        self.msg.integer_array_value = .fromArrayList(&array);
        std.log.info(
            "sequence timer\nmessage location: {*}\npointer location: {*}\nsize: {}\ncapacity: {}",
            .{
                &self.msg,
                self.msg.integer_array_value.data,
                self.msg.integer_array_value.size,
                self.msg.integer_array_value.capacity,
            },
        );
        self.publisher.publish(&self.msg) catch {};
    }
};

pub fn serviceCallback(
    req: *const rcl_interfaces.srv.GetParameters.Request,
    resp: *rcl_interfaces.srv.GetParameters.Response,
) void {
    _ = req;
    _ = resp;
    std.log.info("in service callback");
}

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
    const allocator = gpa.allocator();
    // var allocator = std.heap.c_allocator;
    const rcl_allocator = rclzig.allocator.getDefaultRclAllocator();

    // var allocator = std.heap.c_allocator; // The subscriber middleware seems to be calling free internally.
    // This means that when sequences are used, we're forced to use the c allocator

    var context = try rclzig.init(rcl_allocator);
    defer rclzig.shutdown(&context);

    var clock = try rclzig.time.Clock.init(rcl_allocator, rclzig.time.ClockType.system_time);
    defer clock.deinit();

    var string_node: TestNodeStrings = undefined;
    try string_node.init(rcl_allocator, &clock, &context);
    defer string_node.deinit(rcl_allocator);

    var sequence_node: TestNodeSequences = undefined;
    try sequence_node.init(allocator, rcl_allocator, &clock, &context);
    defer sequence_node.deinit(rcl_allocator);

    var executor = try rclzig.Executor.init(allocator);
    defer executor.deinit();

    try executor.addSubscription(&string_node.subscription);
    try executor.addTimer(&string_node.timer);

    try executor.addSubscription(&sequence_node.subscription);
    try executor.addTimer(&sequence_node.timer);

    try executor.spin(rcl_allocator, &context);

    std.log.info("shuhtting down...", .{});
    return 0;
}
