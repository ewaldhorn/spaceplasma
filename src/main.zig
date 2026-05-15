const std = @import("std");
const types = @import("types.zig");
const SoftwareRenderer = @import("SoftwareRenderer.zig").SoftwareRenderer;

pub const Colour = types.Colour;

// Native high-resolution configuration
pub const screen_width = 800;
pub const screen_height = 600;

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

// Interactive Cursor Wave Projection Caches.
// Trigonometric decomposition allows computing perfect 2D circular Gaussian ripples
// without EVER executing @sqrt() or @exp() in the inner pixel loop!
var mx_sin: [screen_width]f32 = undefined;
var mx_cos: [screen_width]f32 = undefined;
var mx_weight: [screen_width]f32 = undefined;

var my_sin: [screen_height]f32 = undefined;
var my_cos: [screen_height]f32 = undefined;
var my_weight: [screen_height]f32 = undefined;

// State management for live interactive coordinates
pub var mouse_x: f32 = -2000.0; // Park way off screen initially
pub var mouse_y: f32 = -2000.0;
pub var mouse_pressed: bool = false;
pub var ripple_strength: f32 = 0.0;

// Rigid frame clock
pub var internal_clock: f32 = 0.0;

/// Receives real-time scaled interactive coordinates from Javascript driver
pub fn set_mouse_state(mx: f32, my: f32, pressed: bool) void {
    mouse_x = mx;
    mouse_y = my;
    mouse_pressed = pressed;
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

        const r: u8 = @intFromFloat(std.math.clamp(128.0 + 127.0 * @sin(angle + t * 1.5), 0.0, 255.0));
        const g: u8 = @intFromFloat(std.math.clamp(128.0 + 127.0 * @sin(angle + 2.0 - t), 0.0, 255.0));
        const b: u8 = @intFromFloat(std.math.clamp(128.0 + 127.0 * @sin(angle + 4.0 + t * 0.5), 0.0, 255.0));

        palette[i] = Colour.rgba(r, g, b, 255);
    }
}

/// Native 800x600 Highly-Interactive Mathematical Renderer.
pub fn update(real_t: f32) void {
    _ = real_t;

    // Rigid time step
    internal_clock += 0.005;
    const t = internal_clock;

    // 1. Smoothly lerp the active interaction strength (glow in/out dynamics)
    var target_strength: f32 = 0.0;
    // If cursor is within screen bounds
    if (mouse_x >= 0.0 and mouse_x <= @as(f32, @floatFromInt(screen_width))) {
        target_strength = if (mouse_pressed) 1.4 else 0.5;
    }
    ripple_strength += (target_strength - ripple_strength) * 0.1;

    // 2. Pre-populate frame palette
    updatePalette(t);

    // 3. Projection Cache: Base Plasma Equations

    // V1 Projection
    for (0..screen_width) |cx_idx| {
        const cx = @as(f32, @floatFromInt(cx_idx));
        v1_cache[cx_idx] = @sin(cx / 45.0 + t * 1.2);
    }

    // V2 Projection
    for (0..screen_height) |cy_idx| {
        const cy = @as(f32, @floatFromInt(cy_idx));
        v2_cache[cy_idx] = @sin((cy / 35.0 + t * 0.9) * 1.3);
    }

    // V3 Projection
    for (0..(screen_width + screen_height)) |diag1_idx| {
        const ci = @as(f32, @floatFromInt(diag1_idx));
        v3_cache[diag1_idx] = @sin(ci / 50.0 + t * 1.5);
    }

    // V4 Projection
    const height_f = @as(f32, @floatFromInt(screen_height));
    for (0..(screen_width + screen_height)) |diag2_idx| {
        const val = @as(f32, @floatFromInt(diag2_idx)) - height_f;
        v4_cache[diag2_idx] = @sin(val / 70.0 - t * 1.1);
    }

    // 4. Advanced Interaction Projection: Precompute Gaussian Compound Ripple Factors
    if (ripple_strength > 0.001) {
        const ripple_scale: f32 = 1200.0; // Space multiplier for ring frequency
        const radius_sq: f32 = 180.0 * 180.0; // Standard Gaussian falloff radius

        // X dimension factors
        for (0..screen_width) |rx_idx| {
            const cx = @as(f32, @floatFromInt(rx_idx));
            const dx = cx - mouse_x;
            const dx_sq = dx * dx;
            // Expand ripple outwards over time
            const angle = dx_sq / ripple_scale - t * 9.0;
            mx_sin[rx_idx] = @sin(angle);
            mx_cos[rx_idx] = @cos(angle);
            mx_weight[rx_idx] = @exp(-dx_sq / radius_sq);
        }

        // Y dimension factors
        for (0..screen_height) |ry_idx| {
            const cy = @as(f32, @floatFromInt(ry_idx));
            const dy = cy - mouse_y;
            const dy_sq = dy * dy;
            const angle = dy_sq / ripple_scale;
            my_sin[ry_idx] = @sin(angle);
            my_cos[ry_idx] = @cos(angle);
            my_weight[ry_idx] = @exp(-dy_sq / radius_sq);
        }
    }

    // 5. Unified Rendering Loop
    const strength = ripple_strength;
    const has_ripple = strength > 0.001;

    const pixels: *[screen_width * screen_height]Colour = @ptrCast(&buffer);

    for (0..screen_height) |y| {
        const v2 = v2_cache[y];

        // Pre-fetch Y-ripple projections once per row
        const mys = if (has_ripple) my_sin[y] else 0.0;
        const myc = if (has_ripple) my_cos[y] else 0.0;
        const myw = if (has_ripple) my_weight[y] else 0.0;

        const row_idx = y * screen_width;

        for (0..screen_width) |x| {
            const v1 = v1_cache[x];
            const v3 = v3_cache[x + y];
            const v4 = v4_cache[x + screen_height - y];

            // Compound wave construction
            var composite = v1 + v2 + v3 + v4;

            // Dynamic Interactive Ripple Injection
            if (has_ripple) {
                // 1D Cos/Sin fetch
                const mxs = mx_sin[x];
                const mxc = mx_cos[x];
                const mxw = mx_weight[x];

                // Reconstruct perfect mathematical sin(dx^2 + dy^2) via trigonometric identity
                const concentric_wave = mxs * myc + mxc * mys;

                // Combine 1D Gaussian weights and apply dynamic strength scaler
                const ripple_pixel = concentric_wave * mxw * myw * strength;

                // Inject into composite wave field
                composite += ripple_pixel * 4.0; // 4.0 multiplier for vibrant impact
            }

            // Translate composite range perfectly to the 4096 12-bit palette
            const val_ratio = (composite + 4.0) / 8.0;
            const palette_idx = @as(usize, @intFromFloat(std.math.clamp(val_ratio * 4095.99, 0.0, 4095.0))) & 4095;

            pixels[row_idx + x] = palette[palette_idx];
        }
    }
}
