const std = @import("std");
const types = @import("types.zig");
const SoftwareRenderer = @import("SoftwareRenderer.zig").SoftwareRenderer;

pub const Colour = types.Colour;

// Mobile-optimised native resolution configuration (4x lower compute load)
pub const screen_width = 400;
pub const screen_height = 300;

// Declare screen buffer
pub var buffer: [screen_width * screen_height * 4]u8 = undefined;

// Setup the Software Renderer engine
const Engine = SoftwareRenderer(screen_width, screen_height, &buffer);

// High-Fidelity dynamic frame palette
var palette: [4096]Colour = undefined;

// Main 1D Cache Projections
var v1_cache: [screen_width]f32 = undefined;
var v2_cache: [screen_height]f32 = undefined;
var v3_cache: [screen_width + screen_height]f32 = undefined;
var v4_cache: [screen_width + screen_height]f32 = undefined;

// Interactive Cursor Wave Projection Caches for up to 4 concurrent touch points.
// Trigonometric decomposition allows computing perfect 2D circular Gaussian ripples
// without EVER executing @sqrt() or @exp() in the inner pixel loop!
var mx_sin: [4][screen_width]f32 = undefined;
var mx_cos: [4][screen_width]f32 = undefined;
var mx_weight: [4][screen_width]f32 = undefined;

var my_sin: [4][screen_height]f32 = undefined;
var my_cos: [4][screen_height]f32 = undefined;
var my_weight: [4][screen_height]f32 = undefined;

// Touch point definitions
pub const TouchPoint = struct {
    x: f32 = -2000.0, // Park way off screen initially
    y: f32 = -2000.0,
    pressed: bool = false,
    active: bool = false,
    ripple_strength: f32 = 0.0,
};

// State management for live interactive coordinates (4 parallel channels)
pub var touch_points = [_]TouchPoint{.{}} ** 4;

// Rigid frame clock
pub var internal_clock: f32 = 0.0;

/// Receives real-time scaled interactive coordinates from Javascript driver for specific touch channel
pub fn set_touch_state(index: usize, mx: f32, my: f32, pressed: bool, active: bool) void {
    if (index >= 4) return;
    touch_points[index].x = mx;
    touch_points[index].y = my;
    touch_points[index].pressed = pressed;
    touch_points[index].active = active;
}

/// Initializes standard application state
pub fn init() void {
    Engine.clear(Colour.black);
}

/// Precomputes the frame-specific colour palette entries
fn updatePalette(t: f32) void {
    for (0..4096) |i| {
        const ratio = @as(f32, @floatFromInt(i)) / 4095.0;
        const angle = ratio * std.math.pi * 2.0;

        const r: u8 = @intFromFloat(128.0 + 127.0 * @sin(angle + t * 1.5));
        const g: u8 = @intFromFloat(128.0 + 127.0 * @sin(angle + 2.0 - t));
        const b: u8 = @intFromFloat(128.0 + 127.0 * @sin(angle + 4.0 + t * 0.5));

        palette[i] = Colour.rgba(r, g, b, 255);
    }
}

/// Native 400x300 Highly-Interactive Mathematical Renderer.
pub fn update(real_t: f32) void {
    _ = real_t;

    // Rigid time step
    internal_clock += 0.005;
    const t = internal_clock;

    // Internal spatial scale factor to perfectly match 800x600 mathematical visual frequency
    const scale_factor: f32 = 2.0;

    // 1. Smoothly lerp the active interaction strength for each touch channel (glow in/out dynamics)
    inline for (0..4) |i| {
        const point = &touch_points[i];
        var target_strength: f32 = 0.0;
        if (point.active and point.x >= 0.0 and point.x <= @as(f32, @floatFromInt(screen_width))) {
            target_strength = if (point.pressed) 1.4 else 0.5;
        }
        point.ripple_strength += (target_strength - point.ripple_strength) * 0.1;
    }

    // 2. Pre-populate frame palette
    updatePalette(t);

    // 3. Projection Cache: Base Plasma Equations

    // V1 Projection
    for (0..screen_width) |cx_idx| {
        const cx = @as(f32, @floatFromInt(cx_idx)) * scale_factor;
        v1_cache[cx_idx] = @sin(cx / 45.0 + t * 1.2);
    }

    // V2 Projection
    for (0..screen_height) |cy_idx| {
        const cy = @as(f32, @floatFromInt(cy_idx)) * scale_factor;
        v2_cache[cy_idx] = @sin((cy / 35.0 + t * 0.9) * 1.3);
    }

    // V3 Projection
    for (0..(screen_width + screen_height)) |diag1_idx| {
        const ci = @as(f32, @floatFromInt(diag1_idx)) * scale_factor;
        v3_cache[diag1_idx] = @sin(ci / 50.0 + t * 1.5);
    }

    // V4 Projection
    const height_f = @as(f32, @floatFromInt(screen_height));
    for (0..(screen_width + screen_height)) |diag2_idx| {
        const val = (@as(f32, @floatFromInt(diag2_idx)) - height_f) * scale_factor;
        v4_cache[diag2_idx] = @sin(val / 70.0 - t * 1.1);
    }

    // 4. Advanced Interaction Projection: Precompute Gaussian Compound Ripple Factors for all touch points
    const ripple_scale: f32 = 1200.0; // Space multiplier for ring frequency
    const radius_sq: f32 = 180.0 * 180.0; // Standard Gaussian falloff radius

    inline for (0..4) |i| {
        const point = &touch_points[i];
        if (point.ripple_strength > 0.001) {
            const scaled_mouse_x = point.x * scale_factor;
            const scaled_mouse_y = point.y * scale_factor;

            // X dimension factors
            for (0..screen_width) |rx_idx| {
                const cx = @as(f32, @floatFromInt(rx_idx)) * scale_factor;
                const dx = cx - scaled_mouse_x;
                const dx_sq = dx * dx;
                // Expand ripple outwards over time
                const angle = dx_sq / ripple_scale - t * 9.0;
                mx_sin[i][rx_idx] = @sin(angle);
                mx_cos[i][rx_idx] = @cos(angle);
                mx_weight[i][rx_idx] = @exp(-dx_sq / radius_sq);
            }

            // Y dimension factors
            for (0..screen_height) |ry_idx| {
                const cy = @as(f32, @floatFromInt(ry_idx)) * scale_factor;
                const dy = cy - scaled_mouse_y;
                const dy_sq = dy * dy;
                const angle = dy_sq / ripple_scale;
                my_sin[i][ry_idx] = @sin(angle);
                my_cos[i][ry_idx] = @cos(angle);
                my_weight[i][ry_idx] = @exp(-dy_sq / radius_sq);
            }
        }
    }

    // 5. Unified Rendering Loop
    var has_ripple = false;
    inline for (0..4) |i| {
        if (touch_points[i].ripple_strength > 0.001) {
            has_ripple = true;
        }
    }

    const pixels: *[screen_width * screen_height]Colour = @ptrCast(&buffer);

    // Loop unswitching: By completely separating the outer conditional check,
    // the compiler can auto-vectorize the branch-free loops for massive performance gains!
    if (has_ripple) {
        for (0..screen_height) |y| {
            const v2 = v2_cache[y];
            const y_inv = screen_height - y;

            // Pre-fetch Y-ripple projections once per row for all points
            var mys: [4]f32 = undefined;
            var myc: [4]f32 = undefined;
            var myw_str: [4]f32 = undefined; // my_weight * strength
            inline for (0..4) |i| {
                const strength = touch_points[i].ripple_strength;
                mys[i] = my_sin[i][y];
                myc[i] = my_cos[i][y];
                myw_str[i] = if (strength > 0.001) my_weight[i][y] * strength else 0.0;
            }

            const row_idx = y * screen_width;

            for (0..screen_width) |x| {
                const v1 = v1_cache[x];
                const v3 = v3_cache[x + y];
                const v4 = v4_cache[x + y_inv];

                // Compound wave construction
                var composite = v1 + v2 + v3 + v4;

                // Dynamic Interactive Ripple Injection
                var ripple_pixel: f32 = 0.0;
                inline for (0..4) |i| {
                    const mxs = mx_sin[i][x];
                    const mxc = mx_cos[i][x];
                    const mxw = mx_weight[i][x];

                    // Reconstruct perfect mathematical sin(dx^2 + dy^2) via trigonometric identity
                    const concentric_wave = mxs * myc[i] + mxc * mys[i];

                    // Combine 1D Gaussian weights and apply dynamic strength scaler
                    ripple_pixel += concentric_wave * mxw * myw_str[i];
                }

                // Inject into composite wave field
                composite += ripple_pixel * 4.0; // 4.0 multiplier for vibrant impact

                // Translate composite range perfectly to the 4096 12-bit palette
                const val_scaled = (composite + 4.0) * 512.0;
                const palette_idx = @as(usize, @intFromFloat(std.math.clamp(val_scaled, 0.0, 4095.0)));

                pixels[row_idx + x] = palette[palette_idx];
            }
        }
    } else {
        for (0..screen_height) |y| {
            const v2 = v2_cache[y];
            const y_inv = screen_height - y;
            const row_idx = y * screen_width;

            for (0..screen_width) |x| {
                const v1 = v1_cache[x];
                const v3 = v3_cache[x + y];
                const v4 = v4_cache[x + y_inv];

                // Compound wave construction
                const composite = v1 + v2 + v3 + v4;

                // Translate composite range perfectly to the 4096 12-bit palette
                const val_scaled = (composite + 4.0) * 512.0;
                const palette_idx = @as(usize, @intFromFloat(std.math.clamp(val_scaled, 0.0, 4095.0)));

                pixels[row_idx + x] = palette[palette_idx];
            }
        }
    }
}
