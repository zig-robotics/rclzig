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
    system_default = 0,
    transient_local = 1,
    volatilee = 2,
    unknown = 3,
    best_available = 4,
};

pub const QosLivelinessPolicy = enum(c_uint) {
    system_default = 0,
    automatic = 1,
    manual_by_node = 2,
    manual_by_topic = 3,
    unknown = 4,
    best_available = 5,
};

pub const Time = extern struct {
    sec: u64,
    nsec: u64,
};

// TODO link where these defaults match the rcl
// And test it
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

pub const UniqueNetworkFlowEndpointsRequirement = enum(c_uint) {
    not_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_NOT_REQUIRED,
    strictly_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_STRICTLY_REQUIRED,
    optionally_required = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_OPTIONALLY_REQUIRED,
    system_default = rcl.RMW_UNIQUE_NETWORK_FLOW_ENDPOINTS_SYSTEM_DEFAULT,
};

pub const RmwEventCallback = ?*const fn (?*const anyopaque, usize) callconv(.C) void;
pub const RclEventCallback = RmwEventCallback;
