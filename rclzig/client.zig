const rcl = @import("rcl.zig").rcl;

const std = @import("std");
const rcl_allocator = @import("allocator.zig");
const Node = @import("node.zig").Node;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");

fn initClient(
    allocator: rcl_allocator.RclAllocator,
    node: *Node,
    comptime SrvT: type,
    topic_name: [:0]const u8,
    qos: rmw.QosProfile,
) !rcl.rcl_client_t {
    var client = rcl.rcl_get_zero_initialized_client();
    var options = rcl.rcl_client_get_default_options();
    options.qos = qos.rcl().*;
    options.allocator = allocator.rcl_allocator;
    const rc = rcl.rcl_client_init(
        &client,
        &node.rcl_node,
        @ptrCast(SrvT.getTypeSupportHandle()),
        @ptrCast(topic_name),
        &options,
    );

    if (rc != rcl_error.RCL_RET_OK) {
        return rcl_error.intToRclError(rc);
    }

    return client;
}

// The callback should be directly a function
fn ClientCallback(comptime SrvT: type, comptime callback: anytype) type {
    return struct {
        const Self = @This();
        // TODO allow for more callback types like in the subscriptions?
        // TODO add tracking of request as well?
        const CallbackT = @TypeOf(callback);
        const ContextT = switch (@typeInfo(CallbackT)) {
            .@"fn" => |f| blk: {
                if (f.params.len == 2) {
                    if (f.params[1].type) |RespT| if (RespT == *const SrvT.Response) {
                        if (f.params[0].type) |T| {
                            break :blk T;
                        } else {
                            @compileError("First argument does not have a type!");
                        }
                    };
                    @compileError("Callback function " ++ @typeName(CallbackT) ++
                        "does not have correct secnod arg. Must be of type: " ++ @typeName(*const SrvT.Response));
                } else {
                    @compileError("The callback must take two arguments: (anytype, " ++
                        @typeName(*const SrvT.Response) ++ ")");
                }
            },
            else => @compileError("The callback argument must be a function that takes two args: (anytype, " ++
                @typeName(*const SrvT.Response) ++ ")"),
        };
        context: ContextT,
        // TODO in the executor all we have is the response by default. if we want the request it needs to be held on to.
        // Do we really need the request? force the caller to store it in the context?
        pub fn typeErased(self: *anyopaque, resp: *const anyopaque) void {
            callback(@ptrCast(@alignCast(self)), @ptrCast(@alignCast(resp)));
        }

        pub fn call(self: *Self, resp: *const SrvT.Response) void {
            callback(self.context, resp);
        }
    };
}

pub fn Client(comptime SrvT: type, callback: anytype) type {
    return struct {
        const Self = @This();
        pub const CallbackT = ClientCallback(SrvT, callback);
        client: rcl.rcl_client_t,
        callback: CallbackT,
        response: SrvT.Response, // TODO this isn't technically needed, but is nice for static implementations. Consider adding a verion that uses a heap pointer?

        pub fn initBind(
            allocator: rcl_allocator.RclAllocator,
            node: *Node,
            topic_name: [:0]const u8,
            context: CallbackT.ContextT,
        ) !Self {
            return Self{
                // TODO make QoS version available
                .client = try initClient(allocator, node, SrvT, topic_name, .services_default),
                .callback = .{ .context = context },
                .response = undefined, // This gets filled out by the RMW
            };
        }

        pub fn deinit(self: *Self, allocator: rcl_allocator.RclAllocator, node: *Node) void {
            if (comptime std.meta.hasMethod(SrvT.Response, "deinit")) {
                self.response.deinit(allocator);
            }
            // TODO need to decide system wide if we're handling the errors from fini
            // Zig can't throw errors in defers so that makes this awkward
            // In the majority of cases this won't error, but perhaps debug assert / panic when building in debug?
            _ = rcl.rcl_client_fini(&self.client, @ptrCast(node));
        }

        pub fn serviceIsReady(self: *const Self) !bool {
            var is_ready = false;
            const ret = rcl.rcl_service_server_is_available(self.node, self.client, &is_ready);
            if (ret != rcl_error.RCL_RET_OK) return rcl_error.intToRclError(ret);
            return is_ready;
        }

        pub fn sendRequestAsync(self: *const Self, request: *const SrvT.Request) !void {
            // TODO what are we supposed to do with sequence?
            var sequence: i64 = 0;
            const ret = rcl.rcl_send_request(&self.client, @ptrCast(request), &sequence);
            if (ret != rcl_error.RCL_RET_OK) return rcl_error.intToRclError(ret);
        }
    };
}
