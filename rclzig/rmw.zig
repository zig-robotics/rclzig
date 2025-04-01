// TODO sprinkle in sources for these?
// TODO add tests that assert these match the rcl default functions
const rcl = @import("rcl.zig").rcl;
pub const QosReliabilityPolicy = enum(rcl.rmw_qos_reliability_policy_t) {
    system_Default = rcl.RMW_QOS_POLICY_RELIABILITY_SYSTEM_DEFAULT,
    reliable = rcl.RMW_QOS_POLICY_RELIABILITY_RELIABLE,
    best_effort = rcl.RMW_QOS_POLICY_RELIABILITY_BEST_EFFORT,
    unknown = rcl.RMW_QOS_POLICY_RELIABILITY_UNKNOWN,
    best_available = rcl.RMW_QOS_POLICY_RELIABILITY_BEST_AVAILABLE,
};

pub const QosHistoryPolicy = enum(rcl.rmw_qos_history_policy_t) {
    system_default = rcl.RMW_QOS_POLICY_HISTORY_SYSTEM_DEFAULT,
    keep_last = rcl.RMW_QOS_POLICY_HISTORY_KEEP_LAST,
    keep_all = rcl.RMW_QOS_POLICY_HISTORY_KEEP_ALL,
    unknown = rcl.RMW_QOS_POLICY_HISTORY_UNKNOWN,
};

pub const QosDurabilityPolicy = enum(c_uint) {
    system_default = rcl.RMW_QOS_POLICY_DURABILITY_SYSTEM_DEFAULT,
    transient_local = rcl.RMW_QOS_POLICY_DURABILITY_TRANSIENT_LOCAL,
    volatilee = rcl.RMW_QOS_POLICY_DURABILITY_VOLATILE,
    unknown = rcl.RMW_QOS_POLICY_DURABILITY_UNKNOWN,
    best_available = rcl.RMW_QOS_POLICY_DURABILITY_BEST_AVAILABLE,
};

pub const QosLivelinessPolicy = enum(c_uint) {
    system_default = rcl.RMW_QOS_POLICY_LIVELINESS_SYSTEM_DEFAULT,
    automatic = rcl.RMW_QOS_POLICY_LIVELINESS_AUTOMATIC,
    manual_by_node = rcl.RMW_QOS_POLICY_LIVELINESS_MANUAL_BY_NODE,
    manual_by_topic = rcl.RMW_QOS_POLICY_LIVELINESS_MANUAL_BY_TOPIC,
    unknown = rcl.RMW_QOS_POLICY_LIVELINESS_UNKNOWN,
    best_available = rcl.RMW_QOS_POLICY_LIVELINESS_BEST_AVAILABLE,
};

pub const Time = extern struct {
    sec: u64,
    nsec: u64,
};

// Defaults match: https://github.com/ros2/rmw/blob/jazzy/rmw/include/rmw/qos_profiles.h#L51
pub const QosProfile = extern struct {
    history: QosHistoryPolicy = QosHistoryPolicy.keep_last,
    depth: usize = 10,
    reliability: QosReliabilityPolicy = QosReliabilityPolicy.reliable,
    durability: QosDurabilityPolicy = QosDurabilityPolicy.volatilee,
    deadline: Time = Time{
        .sec = 0,
        .nsec = 0,
    },
    lifespan: Time = Time{
        .sec = 0,
        .nsec = 0,
    },
    liveliness: QosLivelinessPolicy = QosLivelinessPolicy.system_default,
    liveliness_lease_duration: Time = Time{
        .sec = 0,
        .nsec = 0,
    },
    avoid_ros_namespace_conventions: bool = false,

    pub fn rcl(self: *const QosProfile) *const @import("rcl.zig").rcl.rmw_qos_profile_t {
        return @ptrCast(self);
    }
};

test "test qos default" {
    const std = @import("std");
    const rcl_default = rcl.rmw_qos_profile_default;
    const rclzig_default = QosProfile{};
    try std.testing.expectEqualSlices(u8, std.mem.asBytes(&rcl_default), std.mem.asBytes(&rclzig_default));
}

pub const UniqueNetworkFlowEndpointsRequirement = enum(c_uint) {
    not_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_NOT_REQUIRED,
    strictly_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_STRICTLY_REQUIRED,
    optionally_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_OPTIONALLY_REQUIRED,
    system_default = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_SYSTEM_DEFAULT,
};

pub const RmwEventCallback = ?*const fn (?*const anyopaque, usize) callconv(.C) void;
pub const RclEventCallback = RmwEventCallback;
