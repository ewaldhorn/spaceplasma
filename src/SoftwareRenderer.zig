const types = @import("types.zig");
pub const Colour = types.Colour;

// ------------------------------------------------------------------------------------------------
pub fn SoftwareRenderer(
    comptime width: u32,
    comptime height: u32,
    comptime buffer: *[width * height * 4]u8,
) type {
    return struct {
        // --------------------------------------------------------------------------------------------
        pub const screen_width = width;
        pub const screen_height = height;

        // --------------------------------------------------------------------------------------------
        pub const shimmer_lut_size = 256;
        pub const shimmer_lut: [shimmer_lut_size]u8 = init: {
            var lut: [shimmer_lut_size]u8 = [_]u8{2} ** shimmer_lut_size; // 2 = Normal
            for (0..shimmer_lut_size) |i| {
                if (i % 7 == 0) {
                    lut[i] = 3; // Bright
                } else if (i % 5 == 0) {
                    lut[i] = 0; // Dim
                } else if (i % 3 == 0) {
                    lut[i] = 1; // Dull
                } else if (i % 2 == 0) {
                    lut[i] = 4; // As-is
                }
            }
            break :init lut;
        };

        // --------------------------------------------------------------------------------------------
        /// Draws a single pixel to the buffer with bounds checking
        pub fn putPixel(x: i32, y: i32, color: Colour) void {
            if (x < 0 or x >= screen_width or y < 0 or y >= screen_height) return;

            const ux: usize = @intCast(x);
            const uy: usize = @intCast(y);
            const offset = (uy * screen_width + ux) * 4;

            if (color.a == 255) {
                buffer[offset + 0] = color.r;
                buffer[offset + 1] = color.g;
                buffer[offset + 2] = color.b;
                buffer[offset + 3] = 255;
            } else if (color.a > 0) {
                // Alpha blending: dst = (src * a + dst * (255 - a)) / 255
                const a = @as(u32, color.a);
                const inv_a = 255 - a;

                buffer[offset + 0] = @as(u8, @intCast((@as(u32, color.r) * a + @as(u32, buffer[offset + 0]) * inv_a) / 255));
                buffer[offset + 1] = @as(u8, @intCast((@as(u32, color.g) * a + @as(u32, buffer[offset + 1]) * inv_a) / 255));
                buffer[offset + 2] = @as(u8, @intCast((@as(u32, color.b) * a + @as(u32, buffer[offset + 2]) * inv_a) / 255));
                buffer[offset + 3] = 255; // Keep target buffer fully opaque
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a line between two points using Bresenham's Line Algorithm
        pub fn drawLine(x1: i32, y1: i32, x2: i32, y2: i32, colour: Colour) void {
            const dx = if (x1 > x2) x1 - x2 else x2 - x1;
            const dy = if (y1 > y2) y1 - y2 else y2 - y1;
            const sx: i32 = if (x1 < x2) 1 else -1;
            const sy: i32 = if (y1 < y2) 1 else -1;
            var err = dx - dy;

            var x = x1;
            var y = y1;

            while (true) {
                putPixel(x, y, colour);
                if (x == x2 and y == y2) break;
                const e2 = 2 * err;
                if (e2 > -dy) {
                    err -= dy;
                    x += sx;
                }
                if (e2 < dx) {
                    err += dx;
                    y += sy;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws the outline of a rectangle
        pub fn drawRect(x: i32, y: i32, w: i32, h: i32, colour: Colour) void {
            if (w <= 0 or h <= 0) return;
            const x2 = x + w - 1;
            const y2 = y + h - 1;

            drawLine(x, y, x2, y, colour);
            drawLine(x, y2, x2, y2, colour);
            drawLine(x, y, x, y2, colour);
            drawLine(x2, y, x2, y2, colour);
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a filled rectangle
        pub fn fillRect(x: i32, y: i32, w: i32, h: i32, colour: Colour) void {
            if (w <= 0 or h <= 0) return;
            const uw: usize = @intCast(w);
            const uh: usize = @intCast(h);

            for (0..uh) |dy| {
                for (0..uw) |dx| {
                    putPixel(x + @as(i32, @intCast(dx)), y + @as(i32, @intCast(dy)), colour);
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws the outline of a circle using the Midpoint Circle Algorithm
        pub fn drawCircle(centerX: i32, centerY: i32, radius: i32, colour: Colour) void {
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                putPixel(centerX + x, centerY + y, colour);
                putPixel(centerX + y, centerY + x, colour);
                putPixel(centerX - y, centerY + x, colour);
                putPixel(centerX - x, centerY + y, colour);
                putPixel(centerX - x, centerY - y, colour);
                putPixel(centerX - y, centerY - x, colour);
                putPixel(centerX + y, centerY - x, colour);
                putPixel(centerX + x, centerY - y, colour);

                if (err <= 0) {
                    y += 1;
                    err += 2 * y + 1;
                }
                if (err > 0) {
                    x -= 1;
                    err -= 2 * x + 1;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a dashed circle outline using the Midpoint Circle Algorithm
        pub fn drawDashedCircle(centerX: i32, centerY: i32, radius: i32, colour: Colour) void {
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                if (@mod(y, 12) < 6) {
                    putPixel(centerX + x, centerY + y, colour);
                    putPixel(centerX + y, centerY + x, colour);
                    putPixel(centerX - y, centerY + x, colour);
                    putPixel(centerX - x, centerY + y, colour);
                    putPixel(centerX - x, centerY - y, colour);
                    putPixel(centerX - y, centerY - x, colour);
                    putPixel(centerX + y, centerY - x, colour);
                    putPixel(centerX + x, centerY - y, colour);
                }

                if (err <= 0) {
                    y += 1;
                    err += 2 * y + 1;
                }
                if (err > 0) {
                    x -= 1;
                    err -= 2 * x + 1;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a shimmer circle for utility shields with performance-optimised LUT lookup
        pub fn drawShimmerCircle(centerX: i32, centerY: i32, radius: i32, colour: Colour, offset: usize) void {
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;
            var count: usize = offset;

            while (x >= y) {
                shimmerPutPixel(centerX + x, centerY + y, colour, &count);
                shimmerPutPixel(centerX + y, centerY + x, colour, &count);
                shimmerPutPixel(centerX - y, centerY + x, colour, &count);
                shimmerPutPixel(centerX - x, centerY + y, colour, &count);
                shimmerPutPixel(centerX - x, centerY - y, colour, &count);
                shimmerPutPixel(centerX - y, centerY - x, colour, &count);
                shimmerPutPixel(centerX + y, centerY - x, colour, &count);
                shimmerPutPixel(centerX + x, centerY - y, colour, &count);

                if (err <= 0) {
                    y += 1;
                    err += 2 * y + 1;
                }
                if (err > 0) {
                    x -= 1;
                    err -= 2 * x + 1;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        fn shimmerPutPixel(x: i32, y: i32, colour: Colour, count: *usize) void {
            const val = shimmer_lut[count.* % shimmer_lut_size];
            count.* += 1;

            var c = colour;

            if (val == 0) { // Dim
                c.r = @intCast(@max(0, @as(i32, c.r) - 5));
                c.g = @intCast(@max(0, @as(i32, c.g) - 5));
                c.b = @intCast(@max(0, @as(i32, c.b) - 5));
                c.a = @intCast(@max(20, @as(i32, c.a) - 20));
            } else if (val == 1) { // Dull
                c.r = @intCast(@max(0, @as(i32, c.r) - 10));
                c.g = @intCast(@max(0, @as(i32, c.g) - 10));
                c.b = @intCast(@max(0, @as(i32, c.b) - 10));
                c.a = @intCast(@max(20, @as(i32, c.a) - 40));
            } else if (val == 3) { // Bright
                c.r = @intCast(@min(255, @as(u32, c.r) + 5));
                c.g = @intCast(@min(255, @as(u32, c.g) + 5));
                c.b = @intCast(@min(255, @as(u32, c.b) + 5));
                c.a = @intCast(@min(255, @as(u32, c.a) + 30));
            } else if (val == 4) {
                c.a = @intCast(@max(10, @as(i32, c.a) - 100)); // Very faint pixels
            }

            putPixel(x, y, c);
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a filled circle
        pub fn fillCircle(centerX: i32, centerY: i32, radius: i32, colour: Colour) void {
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                // Draw horizontal lines to fill the circle
                inline for ([_]i32{ -1, 1 }) |sign_y| {
                    const row_y1 = centerY + sign_y * y;
                    const row_y2 = centerY + sign_y * x;

                    // Lines for y
                    var ix: i32 = centerX - x;
                    while (ix <= centerX + x) : (ix += 1) {
                        putPixel(ix, row_y1, colour);
                    }

                    // Lines for x
                    ix = centerX - y;
                    while (ix <= centerX + y) : (ix += 1) {
                        putPixel(ix, row_y2, colour);
                    }
                }

                if (err <= 0) {
                    y += 1;
                    err += 2 * y + 1;
                }
                if (err > 0) {
                    x -= 1;
                    err -= 2 * x + 1;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Clears the screen with a specific color
        pub fn clear(color: Colour) void {
            for (0..screen_width * screen_height) |i| {
                const offset = i * 4;
                buffer[offset + 0] = color.r;
                buffer[offset + 1] = color.g;
                buffer[offset + 2] = color.b;
                buffer[offset + 3] = color.a;
            }
        }
    };
}
