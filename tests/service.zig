const std = @import("std");
const rclzig = @import("rclzig");
const GetParameters = @import("rcl_interfaces").srv.GetParameters;
const ParameterValue = @import("rcl_interfaces").msg.ParameterValue;

test "test service init and deinit" {
    const Context = struct {
        const Self = @This();
        my_int: isize = 0,

        allocator: std.mem.Allocator,

        pub fn callback(self: *Self, req: *const GetParameters.Request, resp: *GetParameters.Response) void {
            self.my_int += req.names.size;
            resp.values.append(self.allocator, ParameterValue.init(self.allocator) catch @panic("OOM"));
        }
    };

    var allocator = std.testing.allocator;
    const ros_allocator = rclzig.RclAllocator.initFromZig(&allocator);

    var ros_context = try rclzig.init(ros_allocator);
    defer rclzig.shutdown(&ros_context);

    var node = try rclzig.Node.init(ros_allocator, "test", &ros_context);
    defer node.deinit();

    var context = Context{ .allocator = allocator };
    var service = try rclzig.service.Service(GetParameters, Context.callback).initBind(
        ros_allocator,
        &node,
        "test",
        rclzig.rmw.QosProfile.services_default,
        &context,
    );
    service.deinitRequestResponse(&node, ros_allocator, ros_allocator);
}
