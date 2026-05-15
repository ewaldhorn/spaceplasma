// ------------------------------------------------------------------------------------------------
// WASM Bridge Layer
// Exports functions to JavaScript to decouple business logic from standard interface
// ------------------------------------------------------------------------------------------------

const std = @import("std");
const main = @import("main.zig");

/// Initializes application state and clears the screen buffer.
pub export fn init() void {
    main.init();
}

/// Performs a single tick/step logic, generating the new pixel buffer frame.
/// Called by the browser animation frame loop.
pub export fn update(t: f32) void {
    main.update(t);
}

/// Exposes direct memory access pointer to the main RGBA screen buffer (800x600x4 bytes).
/// Fast, direct copying via WebAssembly.Memory into Javascript TypedArray.
pub export fn get_buffer_ptr() [*]u8 {
    return &main.buffer;
}

/// Passes high-fidelity mouse and touch interaction state directly into the engine core.
pub export fn set_mouse_state(mx: f32, my: f32, pressed: bool) void {
    main.set_mouse_state(mx, my, pressed);
}
