const std = @import("std");

// Native simulation grid dimensions
pub const screen_width = 800;
pub const screen_height = 600;

// Touch point definition
pub const TouchPoint = struct {
    x: f32 = -2000.0, // Park way off screen initially
    y: f32 = -2000.0,
    pressed: bool = false,
    active: bool = false,
    ripple_strength: f32 = 0.0,
};

// State management for live interactive coordinates (10 parallel channels)
pub var touch_points = [_]TouchPoint{.{}} ** 10;

// Flat data exported to WebGL fragment shader: [x0, y0, strength0, x1, y1, strength1, ...]
pub var touch_data: [10 * 3]f32 = [_]f32{0.0} ** 30;

// Rigid frame clock
pub var internal_clock: f32 = 0.0;

/// Receives real-time scaled interactive coordinates from Javascript driver for specific touch channel
pub fn set_touch_state(index: usize, mx: f32, my: f32, pressed: bool, active: bool) void {
    if (index >= 10) return;
    touch_points[index].x = mx;
    touch_points[index].y = my;
    touch_points[index].pressed = pressed;
    touch_points[index].active = active;
}

/// Initializes standard application state
pub fn init() void {
    // Initialize touch_data off-screen
    for (0..10) |i| {
        touch_data[i * 3 + 0] = -2000.0;
        touch_data[i * 3 + 1] = -2000.0;
        touch_data[i * 3 + 2] = 0.0;
    }
}

/// Native highly-interactive simulation clock and kinematics step.
pub fn update(real_t: f32) void {
    _ = real_t;

    // Rigid time step
    internal_clock += 0.005;

    // 1. Smoothly lerp the active interaction strength for each touch channel (glow in/out dynamics)
    inline for (0..10) |i| {
        const point = &touch_points[i];
        var target_strength: f32 = 0.0;
        if (point.active and point.x >= 0.0 and point.x <= @as(f32, @floatFromInt(screen_width))) {
            target_strength = if (point.pressed) 1.4 else 0.5;
        }
        point.ripple_strength += (target_strength - point.ripple_strength) * 0.1;

        // Populate flat array for fast direct WebGL uniform mapping
        touch_data[i * 3 + 0] = point.x;
        touch_data[i * 3 + 1] = point.y;
        touch_data[i * 3 + 2] = point.ripple_strength;
    }
}
