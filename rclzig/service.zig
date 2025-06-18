const rcl = @import("rcl.zig").rcl;

const std = @import("std");
const rcl_allocator = @import("allocator.zig");
const Node = @import("node.zig").Node;
const rmw = @import("rmw.zig");
const rcl_error = @import("error.zig");

fn initService(
    allocator: rcl_allocator.RclAllocator,
    node: *Node,
    comptime SrvT: type,
    topic_name: [:0]const u8,
    qos: rmw.QosProfile,
) !rcl.rcl_service_t {
    var service = rcl.rcl_get_zero_initialized_service();
    var options = rcl.rcl_service_get_default_options();
    options.qos = qos.rcl().*;
    options.allocator = allocator.rcl_allocator;
    const rc = rcl.rcl_service_init(
        &service,
        &node.rcl_node,
        @ptrCast(SrvT.getTypeSupportHandle()),
        @ptrCast(topic_name),
        &options,
    );

    if (rc != rcl_error.RCL_RET_OK) {
        return rcl_error.intToRclError(rc);
    }

    return service;
}

// The callback should be directly a function
pub fn ServiceCallback(comptime SrvT: type, comptime callback: anytype) type {
    const Signature = enum {
        request_response,
        request_response_context,
    };
    const CallbackT = @TypeOf(callback);
    const callback_info = switch (@typeInfo(CallbackT)) {
        .@"fn" => |f| blk: {
            // if (f.params.len == 1) {
            //     if (f.params[0].type) |MT| if (MT == *const SrvT) {
            //         break :blk .{ .type = void, .signature = Signature.msg };
            //     };
            //     @compileError("Callback function: " ++ @typeName(CallbackT) ++
            //         " has only one arg, but does not match specified message type: " ++
            //         @typeName(*const SrvT));
            if (f.params.len == 2) {
                // TODO stateless services not supported in the executor yet
                if (f.params[0].type) |ReqT| if (ReqT == *const SrvT.Request) {
                    if (f.params[1].type) |RespT| if (RespT == *SrvT.Response) {
                        break :blk .{ .type = void, .signature = Signature.request_response };
                    };
                    @compileError("Callback function " ++ @typeName(CallbackT) ++
                        " has two args, but the second is not of type " ++ @typeName(*SrvT.Response));
                };
                @compileError("Callback function: " ++ @typeName(CallbackT) ++
                    " has two args, but the first arg does not match specified message type: " ++
                    @typeName(*const SrvT.Request));
            } else if (f.params.len == 3) {
                if (f.params[1].type) |ReqT| if (ReqT == *const SrvT.Request) {
                    if (f.params[2].type) |RespT| if (RespT == *SrvT.Response) {
                        if (f.params[0].type) |T| {
                            break :blk .{ .type = T, .signature = Signature.request_response_context };
                        }
                        @compileError("Callback function " ++ @typeName(CallbackT) ++
                            " has three args, but the first arg is not a is not a type");
                    };
                    @compileError("Callback function " ++ @typeName(CallbackT) ++
                        " has three args, but the third arg is not of type " ++ @typeName(*SrvT.Response));
                };
                @compileError("Callback function: " ++ @typeName(CallbackT) ++
                    " has three args, but the second arg does not match specified message type: " ++
                    @typeName(*const SrvT.Request));
            } else {
                @compileError("Callback function: " ++ @typeName(CallbackT) ++
                    " has incorrect number of args. Must take 2 args (request, response) or 3 args (request, response, context)");
            }
            // } else if (f.params.len == 2) {
            //     if (f.params[1].type) |MT| if (MT == *const SrvT) {
            //         if (f.params[0].type) |T| {
            //             break :blk .{ .type = T, .signature = Signature.context_msg };
            //         }
            //         @compileError("Callback function " ++ @typeName(CallbackT) ++
            //             " has two args, but the first arg is undefined");
            //     };
            //     @compileError("Callback function: " ++ @typeName(CallbackT) ++
            //         " has two args, but second arg does not match specified message type: " ++
            //         @typeName(*const SrvT));
            // }
        },
        else => @compileError("The callback argument must be a function."),
    };

    const signature = callback_info.signature;

    if (signature == .request_response_context) {
        return struct {
            const Self = @This();
            pub const ContextT = callback_info.type;
            pub const stateful = true;
            context: ContextT,

            pub fn typeErased(self: *anyopaque, req: *const anyopaque, resp: *anyopaque) void {
                callback(@ptrCast(@alignCast(self)), @ptrCast(@alignCast(req)), @ptrCast(@alignCast(resp)));
            }

            pub fn call(self: *const Self, req: *const SrvT.Request, resp: *SrvT.Response) void {
                callback(self.context, req, resp);
            }
        };
    } else {
        return struct {
            const Self = @This();
            pub const ContextT = callback_info.type;
            pub const stateful = false;

            // TODO decide if we want to allow callbacks to error. if we do, it should probably be a limited set dictated here otherwise the executor has no way to handle them (OOM for example? maybe we don't allow callbacks to allocate?)
            pub fn typeErased(self: *anyopaque, req: *const anyopaque, resp: *anyopaque) void {
                _ = self;
                callback(@ptrCast(@alignCast(req)), @ptrCast(@alignCast(resp)));
            }

            pub fn call(req: *const SrvT.Request, resp: *SrvT.Response) void {
                callback(req, resp);
            }
        };
    }
}

test "test stateless callback signature" {
    const Srv = struct {
        pub const Request = struct {
            a: i32,
        };
        pub const Response = struct {
            b: i32,
        };
    };
    const Function = struct {
        pub fn callback(req: *const Srv.Request, resp: *Srv.Response) void {
            resp.b = req.a + 1;
        }
    };

    const Callback = ServiceCallback(
        Srv,
        Function.callback,
    );
    var request = Srv.Request{ .a = 1 };
    var response = Srv.Response{ .b = 9 };
    Callback.call(&request, &response);
    try std.testing.expectEqual(2, response.b);

    request.a = 5;
    Callback.typeErased(undefined, @ptrCast(&request), @ptrCast(&response));
    try std.testing.expectEqual(6, response.b);
}

test "test stateful callback signature" {
    const Srv = struct {
        pub const Request = struct {
            a: i32,
        };
        pub const Response = struct {
            b: i32,
        };
    };

    const Context = struct {
        const Self = @This();
        my_int: isize = 0,

        pub fn callback(self: *Self, req: *const Srv.Request, resp: *Srv.Response) void {
            self.my_int += 1;
            resp.b = req.a - 1;
        }
    };

    var context = Context{};
    const service_callback = ServiceCallback(
        Srv,
        Context.callback,
    ){ .context = &context };
    var request = Srv.Request{ .a = 10 };
    var response = Srv.Response{ .b = 2 };
    service_callback.call(&request, &response);
    try std.testing.expectEqual(9, response.b);
    try std.testing.expectEqual(1, context.my_int);

    request.a = 5;
    @TypeOf(service_callback).typeErased(@ptrCast(&context), @ptrCast(&request), @ptrCast(&response));
    try std.testing.expectEqual(4, response.b);
    try std.testing.expectEqual(2, context.my_int);
}

pub fn Service(comptime SrvT: type, comptime callback: anytype) type {
    return struct {
        const Self = @This();
        pub const CallbackT = ServiceCallback(SrvT, callback);
        const request_requires_deinit = std.meta.hasMethod(SrvT.Request, "deinit");
        const response_requires_deinit = std.meta.hasMethod(SrvT.Response, "deinit");
        const DeinitType = enum {
            standard,
            request,
            response,
            request_response,
        };
        const deinit_type: DeinitType = blk: {
            if (!request_requires_deinit and !response_requires_deinit) {
                break :blk .standard;
            } else if (request_requires_deinit and !response_requires_deinit) {
                break :blk .request;
            } else if (!request_requires_deinit and response_requires_deinit) {
                break :blk .response;
            } else if (request_requires_deinit and response_requires_deinit) {
                break :blk .request_response;
            }
            unreachable;
        };

        service: rcl.rcl_service_t,
        request: SrvT.Request, // TODO this isn't technically needed, but is nice for static implementations. Consider adding a verion that uses a heap pointer?
        response: SrvT.Response, // TODO this isn't technically needed, but is nice for static implementations. Consider adding a verion that uses a heap pointer?
        callback: if (CallbackT.stateful) CallbackT else void,

        pub fn init(
            allocator: rcl_allocator.RclAllocator,
            node: *Node,
            service_name: [:0]const u8,
            qos: rmw.QosProfile,
        ) !Self {
            if (CallbackT.stateful)
                @compileError("Normal init called but callback prodvided requires a context pointer to bind to. Please use initBind instead");
            const to_return = Self{
                .service = try initService(allocator, node, SrvT, service_name, qos),
                .request = undefined, // This gets filled out by the RMW
                .response = undefined, // This gets filled out by the application code
                .callback = {},
            };

            // TODO I don't think we need this as the rmw is what always fills these out?
            // errdefer _ = rcl.rcl_subscription_fini(&to_return.subscription, @ptrCast(node));
            // to_return.msg = if (comptime std.meta.hasMethod(SrvT, "init")) try .init(allocator) else .{};

            return to_return;
        }

        pub fn initBind(
            allocator: rcl_allocator.RclAllocator,
            node: *Node,
            service_name: [:0]const u8,
            qos: rmw.QosProfile, // TODO make this the services default?
            context: CallbackT.ContextT,
        ) !Self {
            if (!CallbackT.stateful)
                @compileError("Bind init called but callback prodvided is stateless. Please use init instead");
            const to_return = Self{
                .service = try initService(allocator, node, SrvT, service_name, qos),
                .request = undefined, // This gets filled out by the RMW
                .response = undefined, // This gets filled out by the application code
                .callback = .{ .context = context },
            };

            return to_return;
        }

        // Private deinit that all other deinits can call
        fn deinit_(self: *Self, node: *Node) void {
            // TODO this returns the rcl error, convert it to zig error? (need to consider / be consistent everywhere)
            _ = rcl.rcl_service_fini(&self.service, @ptrCast(node));
        }

        pub fn deinit(self: *Self, node: *Node) void {
            switch (deinit_type) {
                .standard => self.deinit_(node),
                .request => @compileError("Standard deinit called but the internally owned request variable requires " ++
                    "deinitialization with the RMW allocator. Please call deinitRequest instead."),
                .response => @compileError("Standard deinit called but the internally owned response variable requires " ++
                    "deinitialization with the appropriate allocator. Please call deinitResponse instead."),
                .request_response => @compileError("Standard deinit called but the internally owned request and response variables require " ++
                    "deinitialization with the appropriate allocators. Please call deinitReqeustResponse instead."),
            }
        }

        pub fn deinitRequest(self: *Self, node: *Node, rmw_allocator: rcl_allocator.RclAllocator) void {
            // TODO add comptime checks
            self.request.deinit(rmw_allocator);
            self.deinit_(node);
        }

        pub fn deinitResponse(self: *Self, node: *Node, allocator: anytype) void {
            // TODO add comptime checks
            self.response.deinit(allocator);
            self.deinit_(node);
        }

        pub fn deinitRequestResponse(self: *Self, node: *Node, rmw_allocator: rcl_allocator.RclAllocator, allocator: anytype) void {
            // TODO add comptime checks
            self.request.deinit(rmw_allocator);
            self.response.deinit(allocator);
            self.deinit_(node);
        }
    };
}
