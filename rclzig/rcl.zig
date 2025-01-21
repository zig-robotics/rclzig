// This is in its own file so we don't need to make it public in rclzig
// This keeps the rclzig interface cleaner
pub const rcl = @cImport({
    @cInclude("rcl/rcl.h");
});
