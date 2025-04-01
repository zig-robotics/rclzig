const rcl = @import("rcl.zig").rcl;

// https://github.com/ros2/rmw/blob/jazzy/rmw/include/rmw/ret_types.h
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
        .RmwError => return rcl.RMW_RET_ERROR,
        .RmwTimeout => return rcl.RMW_RET_TIMEOUT,
        .RmwUnsupported => return rcl.RMW_RET_UNSUPPORTED,
        .RmwBadAlloc => return rcl.RMW_RET_BAD_ALLOC,
        .RmwInvalidArgument => return rcl.RMW_RET_INVALID_ARGUMENT,
        .RmwIncorrectRmwImplementation => return rcl.RMW_RET_INCORRECT_RMW_IMPLEMENTATION,
        .RmwNodeNameNonExistent => return rcl.RMW_RET_NODE_NAME_NON_EXISTENT,
    }
}

pub fn IntToRmwError(rcl_err: c_int) RmwError {
    switch (rcl_err) {
        rcl.RMW_RET_ERROR => return RmwError.RmwError,
        rcl.RMW_RET_TIMEOUT => return RmwError.RmwTimeout,
        rcl.RMW_RET_UNSUPPORTED => return RmwError.RmwUnsupported,
        rcl.RMW_RET_BAD_ALLOC => return RmwError.RmwBadAlloc,
        rcl.RMW_RET_INVALID_ARGUMENT => return RmwError.RmwInvalidArgument,
        rcl.RMW_RET_INCORRECT_RMW_IMPLEMENTATION => return RmwError.RmwIncorrectRmwImplementation,
        else => return RmwError.RmwError,
    }
}

pub const RCL_RET_OK = rcl.RMW_RET_OK;
pub const RCL_RET_TIMER_CANCELED = rcl.RCL_RET_TIMER_CANCELED; // TODO

// https://github.com/ros2/rcl/blob/jazzy/rcl/include/rcl/types.h#L27
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
        .RclError => return rcl.RCL_RET_ERROR,
        .RclTimeout => return rcl.RCL_RET_TIMEOUT,
        .RclBadAlloc => return rcl.RCL_RET_BAD_ALLOC,
        .RclInvalidArgument => return rcl.RCL_RET_INVALID_ARGUMENT,
        .RclUnsupported => return rcl.RCL_RET_UNSUPPORTED,
        .RclAlreadyInit => return rcl.RCL_RET_ALREADY_INIT,
        .RclNotInit => return rcl.RCL_RET_NOT_INIT,
        .RclMismatchedRmwId => return rcl.RCL_RET_MISMATCHED_RMW_ID,
        .RclTopicNameInvalid => return rcl.RCL_RET_TOPIC_NAME_INVALID,
        .RclServiceNameInvalid => return rcl.RCL_RET_SERVICE_NAME_INVALID,
        .RclUnknownSubstitution => return rcl.RCL_RET_UNKNOWN_SUBSTITUTION,
        .RclAlreadyShutdown => return rcl.RCL_RET_ALREADY_SHUTDOWN,
        .RclNodeInvalid => return rcl.RCL_RET_NODE_INVALID,
        .RclNodeInvalidName => return rcl.RCL_RET_NODE_INVALID_NAME,
        .RclNodeInvalidNamespace => return rcl.RCL_RET_NODE_INVALID_NAMESPACE,
        .RclNodeNameNonExistent => return rcl.RCL_RET_NODE_NAME_NON_EXISTENT,
        .RclPublisherInvalid => return rcl.RCL_RET_PUBLISHER_INVALID,
        .RclSubscriptionInvalid => return rcl.RCL_RET_SUBSCRIPTION_INVALID,
        .RclSubscriptionTakeFailed => return rcl.RCL_RET_SUBSCRIPTION_TAKE_FAILED,
        .RclClientInvalid => return rcl.RCL_RET_CLIENT_INVALID,
        .RclClientTakeFailed => return rcl.RCL_RET_CLIENT_TAKE_FAILED,
        .RclServiceInvalid => return rcl.RCL_RET_SERVICE_INVALID,
        .RclServiceTakeFailed => return rcl.RCL_RET_SERVICE_TAKE_FAILED,
        .RclTimerInvalid => return rcl.RCL_RET_TIMER_INVALID,
        .RclTimerCanceled => return rcl.RCL_RET_TIMER_CANCELED,
        .RclWaitSetInvalid => return rcl.RCL_RET_WAIT_SET_INVALID,
        .RclWaitSetEmpty => return rcl.RCL_RET_WAIT_SET_EMPTY,
        .RclWaitSetFull => return rcl.RCL_RET_WAIT_SET_FULL,
        .RclInvalidRemapRule => return rcl.RCL_RET_INVALID_REMAP_RULE,
        .RclWrongLexeme => return rcl.RCL_RET_WRONG_LEXEME,
        .RclInvalidRosArgs => return rcl.RCL_RET_INVALID_ROS_ARGS,
        .RclInvalidParamRule => return rcl.RCL_RET_INVALID_PARAM_RULE,
        .RclInvalidLogLevelRule => return rcl.RCL_RET_INVALID_LOG_LEVEL_RULE,
        .RclEventInvalid => return rcl.RCL_RET_EVENT_INVALID,
        .RclEventTakeFailed => return rcl.RCL_RET_EVENT_TAKE_FAILED,
        .RclLifecycleStateRegistered => return rcl.RCL_RET_LIFECYCLE_STATE_REGISTERED,
        .RclLifecycleStateNotRegistered => return rcl.RCL_RET_LIFECYCLE_STATE_NOT_REGISTERED,
    }
}

// TODO this says "error is ignored" not sure why
pub fn intToRclError(rcl_err: c_int) RclError {
    switch (rcl_err) {
        rcl.RCL_RET_ERROR => return RclError.RclError,
        rcl.RCL_RET_TIMEOUT => return RclError.RclTimeout,
        rcl.RCL_RET_BAD_ALLOC => return RclError.RclBadAlloc,
        rcl.RCL_RET_INVALID_ARGUMENT => return RclError.RclInvalidArgument,
        rcl.RCL_RET_UNSUPPORTED => return RclError.RclUnsupported,
        rcl.RCL_RET_ALREADY_INIT => return RclError.RclAlreadyInit,
        rcl.RCL_RET_NOT_INIT => return RclError.RclNotInit,
        rcl.RCL_RET_MISMATCHED_RMW_ID => return RclError.RclMismatchedRmwId,
        rcl.RCL_RET_TOPIC_NAME_INVALID => return RclError.RclTopicNameInvalid,
        rcl.RCL_RET_SERVICE_NAME_INVALID => return RclError.RclServiceNameInvalid,
        rcl.RCL_RET_UNKNOWN_SUBSTITUTION => return RclError.RclUnknownSubstitution,
        rcl.RCL_RET_ALREADY_SHUTDOWN => return RclError.RclAlreadyShutdown,
        rcl.RCL_RET_NODE_INVALID => return RclError.RclNodeInvalid,
        rcl.RCL_RET_NODE_INVALID_NAME => return RclError.RclNodeInvalidName,
        rcl.RCL_RET_NODE_INVALID_NAMESPACE => return RclError.RclNodeInvalidNamespace,
        rcl.RCL_RET_NODE_NAME_NON_EXISTENT => return RclError.RclNodeNameNonExistent,
        rcl.RCL_RET_PUBLISHER_INVALID => return RclError.RclPublisherInvalid,
        rcl.RCL_RET_SUBSCRIPTION_INVALID => return RclError.RclSubscriptionInvalid,
        rcl.RCL_RET_SUBSCRIPTION_TAKE_FAILED => return RclError.RclSubscriptionTakeFailed,
        rcl.RCL_RET_CLIENT_INVALID => return RclError.RclClientInvalid,
        rcl.RCL_RET_CLIENT_TAKE_FAILED => return RclError.RclClientTakeFailed,
        rcl.RCL_RET_SERVICE_INVALID => return RclError.RclServiceInvalid,
        rcl.RCL_RET_SERVICE_TAKE_FAILED => return RclError.RclServiceTakeFailed,
        rcl.RCL_RET_TIMER_INVALID => return RclError.RclTimerInvalid,
        rcl.RCL_RET_TIMER_CANCELED => return RclError.RclTimerCanceled,
        rcl.RCL_RET_WAIT_SET_INVALID => return RclError.RclWaitSetInvalid,
        rcl.RCL_RET_WAIT_SET_EMPTY => return RclError.RclWaitSetEmpty,
        rcl.RCL_RET_WAIT_SET_FULL => return RclError.RclWaitSetFull,
        rcl.RCL_RET_INVALID_REMAP_RULE => return RclError.RclInvalidRemapRule,
        rcl.RCL_RET_WRONG_LEXEME => return RclError.RclWrongLexeme,
        rcl.RCL_RET_INVALID_ROS_ARGS => return RclError.RclInvalidRosArgs,
        rcl.RCL_RET_INVALID_PARAM_RULE => return RclError.RclInvalidParamRule,
        rcl.RCL_RET_INVALID_LOG_LEVEL_RULE => return RclError.RclInvalidLogLevelRule,
        rcl.RCL_RET_EVENT_INVALID => return RclError.RclEventInvalid,
        rcl.RCL_RET_EVENT_TAKE_FAILED => return RclError.RclEventTakeFailed,
        rcl.RCL_RET_LIFECYCLE_STATE_REGISTERED => return RclError.RclLifecycleStateRegistered,
        rcl.RCL_RET_LIFECYCLE_STATE_NOT_REGISTERED => return RclError.RclLifecycleStateNotRegistered,
        else => return RclError.RclError,
    }
}
