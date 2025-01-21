// TODO these could come direct from the header???
// TODO document where these come from. Seems rcl might be using a global error set?
// https://github.com/ros2/rcl/blob/rolling/rcl/include/rcl/types.h#L27
// https://github.com/ros2/rmw/blob/rolling/rmw/include/rmw/ret_types.h
pub const RMW_RET_OK = @as(c_int, 0);
const RMW_RET_ERROR = @as(c_int, 1);
const RMW_RET_TIMEOUT = @as(c_int, 2);
const RMW_RET_UNSUPPORTED = @as(c_int, 3);
const RMW_RET_BAD_ALLOC = @as(c_int, 10);
const RMW_RET_INVALID_ARGUMENT = @as(c_int, 11);
const RMW_RET_INCORRECT_RMW_IMPLEMENTATION = @as(c_int, 12);
const RMW_RET_NODE_NAME_NON_EXISTENT = @as(c_int, 203);

pub const RmwError = error{
    RmwError,
    RmwTimeout,
    RmwUnsupported,
    RmwBadAlloc,
    RmwInvalidArgument,
    RmwIncorrectRmwImplementation,
    RmwNodeNameNonExistent,
};

pub fn RmwErrorToInt(err: RmwError) c_int {
    switch (err) {
        .RmwError => return RMW_RET_ERROR,
        .RmwTimeout => return RMW_RET_TIMEOUT,
        .RmwUnsupported => return RMW_RET_UNSUPPORTED,
        .RmwBadAlloc => return RMW_RET_BAD_ALLOC,
        .RmwInvalidArgument => return RMW_RET_INVALID_ARGUMENT,
        .RmwIncorrectRmwImplementation => return RMW_RET_INCORRECT_RMW_IMPLEMENTATION,
        .RmwNodeNameNonExistent => return RMW_RET_NODE_NAME_NON_EXISTENT,
    }
}

// TODO this says "error is ignored" not sure why
pub fn IntToRmwError(rcl_err: c_int) RmwError {
    switch (rcl_err) {
        RMW_RET_ERROR => return RmwError.RmwError,
        RMW_RET_TIMEOUT => return RmwError.RmwTimeout,
        RMW_RET_UNSUPPORTED => return RmwError.RmwUnsupported,
        RMW_RET_BAD_ALLOC => return RmwError.RmwBadAlloc,
        RMW_RET_INVALID_ARGUMENT => return RmwError.RmwInvalidArgument,
        RMW_RET_INCORRECT_RMW_IMPLEMENTATION => return RmwError.RmwIncorrectRmwImplementation,
        else => return RmwError.RmwError,
    }
}

pub const RCL_RET_OK = RMW_RET_OK;
const RCL_RET_ERROR = RMW_RET_ERROR;
const RCL_RET_TIMEOUT = RMW_RET_TIMEOUT;
const RCL_RET_BAD_ALLOC = RMW_RET_BAD_ALLOC;
const RCL_RET_INVALID_ARGUMENT = RMW_RET_INVALID_ARGUMENT;
const RCL_RET_UNSUPPORTED = RMW_RET_UNSUPPORTED;
const RCL_RET_ALREADY_INIT = @as(c_int, 100);
const RCL_RET_NOT_INIT = @as(c_int, 101);
const RCL_RET_MISMATCHED_RMW_ID = @as(c_int, 102);
const RCL_RET_TOPIC_NAME_INVALID = @as(c_int, 103);
const RCL_RET_SERVICE_NAME_INVALID = @as(c_int, 104);
const RCL_RET_UNKNOWN_SUBSTITUTION = @as(c_int, 105);
const RCL_RET_ALREADY_SHUTDOWN = @as(c_int, 106);
const RCL_RET_NODE_INVALID = @as(c_int, 200);
const RCL_RET_NODE_INVALID_NAME = @as(c_int, 201);
const RCL_RET_NODE_INVALID_NAMESPACE = @as(c_int, 202);
const RCL_RET_NODE_NAME_NON_EXISTENT = @as(c_int, 203);
const RCL_RET_PUBLISHER_INVALID = @as(c_int, 300);
const RCL_RET_SUBSCRIPTION_INVALID = @as(c_int, 400);
const RCL_RET_SUBSCRIPTION_TAKE_FAILED = @as(c_int, 401);
const RCL_RET_CLIENT_INVALID = @as(c_int, 500);
const RCL_RET_CLIENT_TAKE_FAILED = @as(c_int, 501);
const RCL_RET_SERVICE_INVALID = @as(c_int, 600);
const RCL_RET_SERVICE_TAKE_FAILED = @as(c_int, 601);
const RCL_RET_TIMER_INVALID = @as(c_int, 800);
pub const RCL_RET_TIMER_CANCELED = @as(c_int, 801); // TODO
const RCL_RET_WAIT_SET_INVALID = @as(c_int, 900);
const RCL_RET_WAIT_SET_EMPTY = @as(c_int, 901);
const RCL_RET_WAIT_SET_FULL = @as(c_int, 902);
const RCL_RET_INVALID_REMAP_RULE = @as(c_int, 1001);
const RCL_RET_WRONG_LEXEME = @as(c_int, 1002);
const RCL_RET_INVALID_ROS_ARGS = @as(c_int, 1003);
const RCL_RET_INVALID_PARAM_RULE = @as(c_int, 1010);
const RCL_RET_INVALID_LOG_LEVEL_RULE = @as(c_int, 1020);
const RCL_RET_EVENT_INVALID = @as(c_int, 2000);
const RCL_RET_EVENT_TAKE_FAILED = @as(c_int, 2001);
const RCL_RET_LIFECYCLE_STATE_REGISTERED = @as(c_int, 3000);
const RCL_RET_LIFECYCLE_STATE_NOT_REGISTERED = @as(c_int, 3001);

pub const RclError = error{
    RclError,
    RclTimeout,
    RclBadAlloc,
    RclInvalidArgument,
    RclUnsupported,
    RclAlreadyInit,
    RclNotInit,
    RclMismatchedRmwId,
    RclTopicNameInvalid,
    RclServiceNameInvalid,
    RclUnknownSubstitution,
    RclAlreadyShutdown,
    RclNodeInvalid,
    RclNodeInvalidName,
    RclNodeInvalidNamespace,
    RclNodeNameNonExistent,
    RclPublisherInvalid,
    RclSubscriptionInvalid,
    RclSubscriptionTakeFailed,
    RclClientInvalid,
    RclClientTakeFailed,
    RclServiceInvalid,
    RclServiceTakeFailed,
    RclTimerInvalid,
    RclTimerCanceled,
    RclWaitSetInvalid,
    RclWaitSetEmpty,
    RclWaitSetFull,
    RclInvalidRemapRule,
    RclWrongLexeme,
    RclInvalidRosArgs,
    RclInvalidParamRule,
    RclInvalidLogLevelRule,
    RclEventInvalid,
    RclEventTakeFailed,
    RclLifecycleStateRegistered,
    RclLifecycleStateNotRegistered,
};

pub fn rclErrorToInt(err: RclError) c_int {
    switch (err) {
        .RclError => return RCL_RET_ERROR,
        .RclTimeout => return RCL_RET_TIMEOUT,
        .RclBadAlloc => return RCL_RET_BAD_ALLOC,
        .RclInvalidArgument => return RCL_RET_INVALID_ARGUMENT,
        .RclUnsupported => return RCL_RET_UNSUPPORTED,
        .RclAlreadyInit => return RCL_RET_ALREADY_INIT,
        .RclNotInit => return RCL_RET_NOT_INIT,
        .RclMismatchedRmwId => return RCL_RET_MISMATCHED_RMW_ID,
        .RclTopicNameInvalid => return RCL_RET_TOPIC_NAME_INVALID,
        .RclServiceNameInvalid => return RCL_RET_SERVICE_NAME_INVALID,
        .RclUnknownSubstitution => return RCL_RET_UNKNOWN_SUBSTITUTION,
        .RclAlreadyShutdown => return RCL_RET_ALREADY_SHUTDOWN,
        .RclNodeInvalid => return RCL_RET_NODE_INVALID,
        .RclNodeInvalidName => return RCL_RET_NODE_INVALID_NAME,
        .RclNodeInvalidNamespace => return RCL_RET_NODE_INVALID_NAMESPACE,
        .RclNodeNameNonExistent => return RCL_RET_NODE_NAME_NON_EXISTENT,
        .RclPublisherInvalid => return RCL_RET_PUBLISHER_INVALID,
        .RclSubscriptionInvalid => return RCL_RET_SUBSCRIPTION_INVALID,
        .RclSubscriptionTakeFailed => return RCL_RET_SUBSCRIPTION_TAKE_FAILED,
        .RclClientInvalid => return RCL_RET_CLIENT_INVALID,
        .RclClientTakeFailed => return RCL_RET_CLIENT_TAKE_FAILED,
        .RclServiceInvalid => return RCL_RET_SERVICE_INVALID,
        .RclServiceTakeFailed => return RCL_RET_SERVICE_TAKE_FAILED,
        .RclTimerInvalid => return RCL_RET_TIMER_INVALID,
        .RclTimerCanceled => return RCL_RET_TIMER_CANCELED,
        .RclWaitSetInvalid => return RCL_RET_WAIT_SET_INVALID,
        .RclWaitSetEmpty => return RCL_RET_WAIT_SET_EMPTY,
        .RclWaitSetFull => return RCL_RET_WAIT_SET_FULL,
        .RclInvalidRemapRule => return RCL_RET_INVALID_REMAP_RULE,
        .RclWrongLexeme => return RCL_RET_WRONG_LEXEME,
        .RclInvalidRosArgs => return RCL_RET_INVALID_ROS_ARGS,
        .RclInvalidParamRule => return RCL_RET_INVALID_PARAM_RULE,
        .RclInvalidLogLevelRule => return RCL_RET_INVALID_LOG_LEVEL_RULE,
        .RclEventInvalid => return RCL_RET_EVENT_INVALID,
        .RclEventTakeFailed => return RCL_RET_EVENT_TAKE_FAILED,
        .RclLifecycleStateRegistered => return RCL_RET_LIFECYCLE_STATE_REGISTERED,
        .RclLifecycleStateNotRegistered => return RCL_RET_LIFECYCLE_STATE_NOT_REGISTERED,
    }
}

// TODO this says "error is ignored" not sure why
pub fn intToRclError(rcl_err: c_int) RclError {
    switch (rcl_err) {
        RCL_RET_ERROR => return RclError.RclError,
        RCL_RET_TIMEOUT => return RclError.RclTimeout,
        RCL_RET_BAD_ALLOC => return RclError.RclBadAlloc,
        RCL_RET_INVALID_ARGUMENT => return RclError.RclInvalidArgument,
        RCL_RET_UNSUPPORTED => return RclError.RclUnsupported,
        RCL_RET_ALREADY_INIT => return RclError.RclAlreadyInit,
        RCL_RET_NOT_INIT => return RclError.RclNotInit,
        RCL_RET_MISMATCHED_RMW_ID => return RclError.RclMismatchedRmwId,
        RCL_RET_TOPIC_NAME_INVALID => return RclError.RclTopicNameInvalid,
        RCL_RET_SERVICE_NAME_INVALID => return RclError.RclServiceNameInvalid,
        RCL_RET_UNKNOWN_SUBSTITUTION => return RclError.RclUnknownSubstitution,
        RCL_RET_ALREADY_SHUTDOWN => return RclError.RclAlreadyShutdown,
        RCL_RET_NODE_INVALID => return RclError.RclNodeInvalid,
        RCL_RET_NODE_INVALID_NAME => return RclError.RclNodeInvalidName,
        RCL_RET_NODE_INVALID_NAMESPACE => return RclError.RclNodeInvalidNamespace,
        RCL_RET_NODE_NAME_NON_EXISTENT => return RclError.RclNodeNameNonExistent,
        RCL_RET_PUBLISHER_INVALID => return RclError.RclPublisherInvalid,
        RCL_RET_SUBSCRIPTION_INVALID => return RclError.RclSubscriptionInvalid,
        RCL_RET_SUBSCRIPTION_TAKE_FAILED => return RclError.RclSubscriptionTakeFailed,
        RCL_RET_CLIENT_INVALID => return RclError.RclClientInvalid,
        RCL_RET_CLIENT_TAKE_FAILED => return RclError.RclClientTakeFailed,
        RCL_RET_SERVICE_INVALID => return RclError.RclServiceInvalid,
        RCL_RET_SERVICE_TAKE_FAILED => return RclError.RclServiceTakeFailed,
        RCL_RET_TIMER_INVALID => return RclError.RclTimerInvalid,
        RCL_RET_TIMER_CANCELED => return RclError.RclTimerCanceled,
        RCL_RET_WAIT_SET_INVALID => return RclError.RclWaitSetInvalid,
        RCL_RET_WAIT_SET_EMPTY => return RclError.RclWaitSetEmpty,
        RCL_RET_WAIT_SET_FULL => return RclError.RclWaitSetFull,
        RCL_RET_INVALID_REMAP_RULE => return RclError.RclInvalidRemapRule,
        RCL_RET_WRONG_LEXEME => return RclError.RclWrongLexeme,
        RCL_RET_INVALID_ROS_ARGS => return RclError.RclInvalidRosArgs,
        RCL_RET_INVALID_PARAM_RULE => return RclError.RclInvalidParamRule,
        RCL_RET_INVALID_LOG_LEVEL_RULE => return RclError.RclInvalidLogLevelRule,
        RCL_RET_EVENT_INVALID => return RclError.RclEventInvalid,
        RCL_RET_EVENT_TAKE_FAILED => return RclError.RclEventTakeFailed,
        RCL_RET_LIFECYCLE_STATE_REGISTERED => return RclError.RclLifecycleStateRegistered,
        RCL_RET_LIFECYCLE_STATE_NOT_REGISTERED => return RclError.RclLifecycleStateNotRegistered,
        else => return RclError.RclError,
    }
}

pub const RmwReturn = i32;
pub const RclReturn = RmwReturn;
