const std = @import("std");
const rclzig = @import("rclzig");
const GetParameters = @import("rcl_interfaces").srv.GetParameters;
const ParameterValue = @import("rcl_interfaces").msg.ParameterValue;

test "basic client request response" {
    const ServiceContext = struct {
        const Self = @This();
        callback_count: isize = 0,

        allocator: std.mem.Allocator,

        pub fn callback(self: *Self, req: *const GetParameters.Request, resp: *GetParameters.Response) void {
            self.callback_count += 1;
            std.testing.expectEqual(1, req.names.size) catch @panic("test failed!");
            std.testing.expectEqualSlices(u8, "test", req.names.asSlice()[0].asSlice()) catch @panic("test failed!");
            // TODO i feel like the "ParameterValue" portion of this shouldn't be needed? .init() should just work
            // is this an issue with the fact that it can return an error?
            resp.values.append(self.allocator, ParameterValue.init(self.allocator) catch @panic("OOM")) catch @panic("OOM");
        }
    };
    const ClientContext = struct {
        const Self = @This();
        callback_count: isize = 0,

        pub fn callback(self: *Self, resp: *const GetParameters.Response) void {
            self.callback_count += 1;
            std.testing.expectEqual(1, resp.values.size) catch @panic("test failed!");
        }
    };

    var allocator = std.testing.allocator;
    const ros_allocator = rclzig.RclAllocator.initFromZig(&allocator);
    const rmw_allocator = rclzig.allocator.getDefaultRclAllocator(); // needed for things that interact with the rmw

    var ros_context = try rclzig.init(ros_allocator);
    defer rclzig.shutdown(&ros_context);

    var node = try rclzig.Node.init(ros_allocator, "test", &ros_context);
    defer node.deinit();

    var client_context = ClientContext{};
    // TODO client needs a c allocator since the callback is called with data passed from the rmw?
    // TODO when integrating this with the executor client is going to need a place to store the responce isn't it?
    var client = try rclzig.client.Client(GetParameters, ClientContext.callback).initBind(
        ros_allocator,
        &node,
        "test",
        &client_context,
    );
    defer client.deinit(rmw_allocator, &node); // needs to be rmw allocator since this frees rmw memory

    var service_context = ServiceContext{ .allocator = allocator };
    // TODO same comment here as with client, needs to be C allocator?
    // technically only the service comes from the rmw? or do both?
    var service = try rclzig.service.Service(GetParameters, ServiceContext.callback).initBind(
        ros_allocator,
        &node,
        "test",
        rclzig.rmw.QosProfile.services_default,
        &service_context,
    );
    defer service.deinitRequestResponse(&node, rmw_allocator, service_context.allocator); // takes rmw allocator here since it needs to free rmw memory

    var executor = try rclzig.Executor.init(allocator);
    defer executor.deinit();

    try executor.addService(&service);
    try executor.addClient(&client);
    var request = GetParameters.Request{};
    defer request.deinit(allocator);
    try request.names.append(allocator, try .fromSliceCopy(allocator, "test"));
    try std.testing.expectEqual(1, request.names.size);
    try client.sendRequestAsync(&request);

    try executor.spinOnce(ros_allocator, &ros_context, 1); // should spin server
    try std.testing.expectEqual(1, service_context.callback_count);
    try std.testing.expectEqual(0, client_context.callback_count);

    try executor.spinOnce(ros_allocator, &ros_context, 1); // should spin client
    try std.testing.expectEqual(1, service_context.callback_count);
    try std.testing.expectEqual(1, client_context.callback_count);
}
