# RCLZig

THIS IS A WORK IN PROGRESS!!!!!!

IT IS NOT STABLE, THE API WILL CHANGE!!!!!!

This repo provides a ROS client library for Zig.
It's still currently under development, but open to colaborators.
If you're interested in working on it with me let me know and we can coordinate.


## A bit of history

This project started off by using Zigs translate-c functionality to convert a [node from the `rclc_examples` package](https://github.com/ros2/rclc/blob/iron/rclc_examples/src/example_short_timer_long_subscription.c).
If you're interested it was translated with:

`zig translate-c -I /opt/ros/iron/include/std_msgs/ -I /zig/lib/libc/musl/include/ -I /zig/lib/libc/include/amd64-linux-musl/ -I /zig/lib/libc/include/generic-musl/ -I /opt/ros/iron/include/rosidl_runtime_c/ -I /opt/ros/iron/include/rcutils/ -I /opt/ros/iron/include/rosidl_typesupport_interface/ -I /opt/ros/iron/include/rcl/ -I /opt/ros/iron/include/ -I /opt/ros/iron/include/rmw/ -I /opt/ros/iron/include/rcl_yaml_param_parser/ -I /opt/ros/iron/include/rosidl_dynamic_typesupport/ -I /opt/ros/iron/include/rcl_action/ -I /opt/ros/iron/include/action_msgs/ -I /opt/ros/iron/include/unique_identifier_msgs/ -I /opt/ros/iron/include/builtin_interfaces/ -I /opt/ros/iron/include/service_msgs/ src/rclc/rclc_examples/src/example_short_timer_long_subscription.c  > test.zig` 

The main function needed some help for building to be compatible with zig's main call signature but beyond that it just works.

That's it were done! /s

## Rough design

After playing around with a few iterations of what zig specific features could improve the ergonomics of rcl/rclc, this is where I've generally landed so far.

Focus on nice zig feeling public facing interface.
Internals and lesser used features should be left as C code.
Allocators where applicable should be made explicit, and passed in separately from the options struct (note that the RMW will not use the allocator provided to rcl, so there are a limited number of places where passing the allocator is actually useful).
Duplication of the underlying rcl library should be left to a minimum.
Functionality that is duplicated should be asserted with tests.
For example rcl provides default initializations through function calls, however in many cases it'd be more ziggy to build a duplicate of the structure in zig and provide defaults that way. 
Since the backend remains c, structures that need to be turned ziggy will have an "rcl" member or function that returns the underlying rcl member, or the zig struct cast to the rcl equivalent.
All Enums shall be converted, but use the rcl converted constants and types for compatibility.
Both building against an existing ROS install and ZigROS should be supported.
