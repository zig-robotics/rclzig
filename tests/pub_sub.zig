const std = @import("std");
const rclzig = @import("rclzig");
const ParameterValue = @import("rcl_interfaces").msg.ParameterValue;

const TestNodeSequences = struct {
    const Self = @This();
    node: rclzig.Node,
    publisher: rclzig.publisher.Publisher(ParameterValue),
    subscription: rclzig.subscription.Subscription(ParameterValue, subCallback),
    msg: ParameterValue,
    allocator: std.mem.Allocator,
    msg_received: bool = false,

    // In this node the rcl_allocator is used only for the subscriber
    // Note that a pointer to the internally stored allocator is used. Therefore
    // this object can't be trivially coppied after initialization
    fn init(
        self: *Self,
        allocator: std.mem.Allocator,
        rcl_allocator: rclzig.RclAllocator,
        context: *rclzig.Context,
    ) !void {
        // Get defaults and mark defered initialized elements explicitly
        self.* = .{
            .node = undefined,
            .publisher = undefined,
            .subscription = undefined,
            .msg = try ParameterValue.init(allocator),
            .allocator = allocator,
        };
        errdefer self.msg.deinit(allocator);

        try self.msg.integer_array_value.reserve(allocator, 1000);

        self.node = try rclzig.Node.init(rclzig.RclAllocator.initFromZig(&self.allocator), "test_node_sequence", context);
        errdefer self.node.deinit();

        self.publisher = try rclzig.publisher.Publisher(ParameterValue).init(
            rclzig.RclAllocator.initFromZig(&self.allocator),
            &self.node,
            "test_sequence",
            rclzig.rmw.QosProfile{},
        );
        errdefer self.publisher.deinit(&self.node) catch {};

        self.subscription = try rclzig.subscription.Subscription(ParameterValue, subCallback).initBind(
            rcl_allocator,
            &self.node,
            "test_sequence",
            rclzig.rmw.QosProfile{},
            self,
        );
    }

    pub fn deinit(self: *Self, rcl_allocator: rclzig.RclAllocator) void {
        self.publisher.deinit(&self.node) catch {};
        self.subscription.deinit(rcl_allocator, &self.node);
        self.node.deinit();
        self.msg.deinit(self.allocator);
    }

    fn subCallback(self: *Self, msg: *const ParameterValue) void {
        if (std.mem.eql(i64, msg.integer_array_value.asSlice(), self.msg.integer_array_value.asSlice()))
            self.msg_received = true;
    }

    fn publishMsg(self: *Self) void {
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

test "test publish and subscribe" {
    const allocator = std.testing.allocator;
    const rcl_allocator = rclzig.allocator.getDefaultRclAllocator();

    var context = try rclzig.init(rcl_allocator);
    defer rclzig.shutdown(&context);

    var sequence_node: TestNodeSequences = undefined;
    try sequence_node.init(allocator, rcl_allocator, &context);
    defer sequence_node.deinit(rcl_allocator);

    var executor = try rclzig.Executor.init(allocator);
    defer executor.deinit();

    try executor.addSubscription(&sequence_node.subscription);
    sequence_node.publishMsg();
    try executor.spinOnce(rcl_allocator, &context, 1);

    try std.testing.expect(sequence_node.msg_received);
}
