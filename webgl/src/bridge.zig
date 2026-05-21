// ------------------------------------------------------------------------------------------------
// WASM Bridge Layer
// Exports functions to JavaScript to decouple business logic from standard interface
// ------------------------------------------------------------------------------------------------

const std = @import("std");
const main = @import("main.zig");

/// Initializes application state.
pub export fn init() void {
    main.init();
}

/// Performs a single tick/step logic, simulating active physics.
/// Called by the browser animation frame loop.
pub export fn update(t: f32) void {
    main.update(t);
}

/// Exposes direct memory access pointer to the rigid frame clock.
pub export fn get_internal_clock() f32 {
    return main.internal_clock;
}

/// Exposes direct memory access pointer to the flat touch data array (10 points * 3 floats).
pub export fn get_touch_data_ptr() [*]f32 {
    return &main.touch_data;
}

/// Passes high-fidelity multi-touch interaction state into the engine core.
pub export fn set_touch_state(index: usize, mx: f32, my: f32, pressed: bool, active: bool) void {
    main.set_touch_state(index, mx, my, pressed, active);
}
