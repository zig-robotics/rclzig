const std = @import("std");
const rclzig = @import("rclzig");
const GetParameters = @import("rcl_interfaces").srv.GetParameters;
const ParameterValue = @import("rcl_interfaces").msg.ParameterValue;

test "test client init and deinit" {
    const Context = struct {
        const Self = @This();

        pub fn callback(self: *Self, resp: *const GetParameters.Response) void {
            _ = self;
            _ = resp;
        }
    };

    var allocator = std.testing.allocator;
    const ros_allocator = rclzig.RclAllocator.initFromZig(&allocator);

    var ros_context = try rclzig.init(ros_allocator);
    defer rclzig.shutdown(&ros_context);

    var node = try rclzig.Node.init(ros_allocator, "test", &ros_context);
    defer node.deinit();

    var context = Context{};
    var client = try rclzig.client.Client(GetParameters, Context.callback).initBind(
        ros_allocator,
        &node,
        "test",
        &context,
    );
    client.deinit(ros_allocator, &node);
}
