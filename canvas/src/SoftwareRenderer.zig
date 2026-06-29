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

        const pixels: *[width * height]Colour = @ptrCast(buffer);

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
        /// Fast division by 255 for values in 0..65535
        inline fn div255(val: u32) u32 {
            return (val + 1 + (val >> 8)) >> 8;
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a single pixel to the buffer with bounds checking
        pub fn putPixel(x: i32, y: i32, colour: Colour) void {
            const ux = @as(u32, @bitCast(x));
            const uy = @as(u32, @bitCast(y));
            if (ux >= screen_width or uy >= screen_height) return;

            const index = @as(usize, uy) * screen_width + @as(usize, ux);

            if (colour.a == 255) {
                pixels[index] = colour;
            } else if (colour.a > 0) {
                // Alpha blending: dst = (src * a + dst * (255 - a)) / 255
                const a: u32 = colour.a;
                const inv_a = 255 - a;

                const dst = &pixels[index];
                dst.r = @intCast(div255(@as(u32, colour.r) * a + @as(u32, dst.r) * inv_a));
                dst.g = @intCast(div255(@as(u32, colour.g) * a + @as(u32, dst.g) * inv_a));
                dst.b = @intCast(div255(@as(u32, colour.b) * a + @as(u32, dst.b) * inv_a));
                dst.a = 255; // Keep target buffer fully opaque
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
        /// Draws a horizontal line optimized with direct buffer access
        pub fn drawHLine(x1: i32, x2: i32, y: i32, colour: Colour) void {
            if (@as(u32, @bitCast(y)) >= screen_height) return;

            const start_x = @max(0, @min(x1, x2));
            const end_x = @min(screen_width - 1, @max(x1, x2));

            if (start_x > end_x) return;

            const len: usize = @intCast(end_x - start_x + 1);
            const index = @as(usize, @intCast(y)) * screen_width + @as(usize, @intCast(start_x));

            if (colour.a == 255) {
                @memset(pixels[index .. index + len], colour);
            } else if (colour.a > 0) {
                const a: u32 = colour.a;
                const inv_a = 255 - a;
                const cr: u32 = colour.r;
                const cg: u32 = colour.g;
                const cb: u32 = colour.b;

                for (0..len) |i| {
                    const dst = &pixels[index + i];
                    dst.r = @intCast(div255(cr * a + @as(u32, dst.r) * inv_a));
                    dst.g = @intCast(div255(cg * a + @as(u32, dst.g) * inv_a));
                    dst.b = @intCast(div255(cb * a + @as(u32, dst.b) * inv_a));
                    dst.a = 255; // Keep target buffer fully opaque
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a vertical line optimized with direct buffer access
        pub fn drawVLine(x: i32, y1: i32, y2: i32, colour: Colour) void {
            if (@as(u32, @bitCast(x)) >= screen_width) return;

            const start_y = @max(0, @min(y1, y2));
            const end_y = @min(screen_height - 1, @max(y1, y2));

            if (start_y > end_y) return;

            const len: usize = @intCast(end_y - start_y + 1);
            const ux: usize = @intCast(x);

            if (colour.a == 255) {
                for (0..len) |i| {
                    const index = (@as(usize, @intCast(start_y)) + i) * screen_width + ux;
                    pixels[index] = colour;
                }
            } else if (colour.a > 0) {
                const a: u32 = colour.a;
                const inv_a = 255 - a;
                const cr: u32 = colour.r;
                const cg: u32 = colour.g;
                const cb: u32 = colour.b;

                for (0..len) |i| {
                    const index = (@as(usize, @intCast(start_y)) + i) * screen_width + ux;
                    const dst = &pixels[index];
                    dst.r = @intCast(div255(cr * a + @as(u32, dst.r) * inv_a));
                    dst.g = @intCast(div255(cg * a + @as(u32, dst.g) * inv_a));
                    dst.b = @intCast(div255(cb * a + @as(u32, dst.b) * inv_a));
                    dst.a = 255;
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws the outline of a rectangle
        pub fn drawRect(x: i32, y: i32, w: i32, h: i32, colour: Colour) void {
            if (w <= 0 or h <= 0) return;
            const x2 = x + w - 1;
            const y2 = y + h - 1;

            drawHLine(x, x2, y, colour);
            if (h > 1) {
                drawHLine(x, x2, y2, colour);
            }
            if (h > 2) {
                drawVLine(x, y + 1, y2 - 1, colour);
                if (w > 1) {
                    drawVLine(x2, y + 1, y2 - 1, colour);
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws a filled rectangle
        pub fn fillRect(x: i32, y: i32, w: i32, h: i32, colour: Colour) void {
            if (w <= 0 or h <= 0) return;

            const start_y = @max(0, y);
            const end_y = @min(screen_height - 1, y + h - 1);
            if (start_y > end_y) return;

            const start_x = @max(0, x);
            const end_x = @min(screen_width - 1, x + w - 1);
            if (start_x > end_x) return;

            const len: usize = @intCast(end_x - start_x + 1);

            if (colour.a == 255) {
                var cy = start_y;
                while (cy <= end_y) : (cy += 1) {
                    const index = @as(usize, @intCast(cy)) * screen_width + @as(usize, @intCast(start_x));
                    @memset(pixels[index .. index + len], colour);
                }
            } else if (colour.a > 0) {
                const a: u32 = colour.a;
                const inv_a = 255 - a;
                const cr: u32 = colour.r;
                const cg: u32 = colour.g;
                const cb: u32 = colour.b;

                var cy = start_y;
                while (cy <= end_y) : (cy += 1) {
                    const index = @as(usize, @intCast(cy)) * screen_width + @as(usize, @intCast(start_x));
                    for (0..len) |i| {
                        const dst = &pixels[index + i];
                        dst.r = @intCast(div255(cr * a + @as(u32, dst.r) * inv_a));
                        dst.g = @intCast(div255(cg * a + @as(u32, dst.g) * inv_a));
                        dst.b = @intCast(div255(cb * a + @as(u32, dst.b) * inv_a));
                        dst.a = 255;
                    }
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Draws the outline of a circle using the Midpoint Circle Algorithm
        pub fn drawCircle(center_x: i32, center_y: i32, radius: i32, colour: Colour) void {
            if (radius < 0) return;
            if (radius == 0) {
                putPixel(center_x, center_y, colour);
                return;
            }

            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                putPixel(center_x + x, center_y + y, colour);
                putPixel(center_x - x, center_y + y, colour);
                if (y != 0) {
                    putPixel(center_x + x, center_y - y, colour);
                    putPixel(center_x - x, center_y - y, colour);
                }
                
                if (x != y) {
                    putPixel(center_x + y, center_y + x, colour);
                    putPixel(center_x - y, center_y + x, colour);
                    if (y != 0) {
                        putPixel(center_x + y, center_y - x, colour);
                        putPixel(center_x - y, center_y - x, colour);
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
        /// Draws a dashed circle outline using the Midpoint Circle Algorithm
        pub fn drawDashedCircle(center_x: i32, center_y: i32, radius: i32, colour: Colour) void {
            if (radius < 0) return;
            if (radius == 0) {
                putPixel(center_x, center_y, colour);
                return;
            }

            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;

            while (x >= y) {
                if (@mod(y, 12) < 6) {
                    putPixel(center_x + x, center_y + y, colour);
                    putPixel(center_x - x, center_y + y, colour);
                    if (y != 0) {
                        putPixel(center_x + x, center_y - y, colour);
                        putPixel(center_x - x, center_y - y, colour);
                    }
                    if (x != y) {
                        putPixel(center_x + y, center_y + x, colour);
                        putPixel(center_x - y, center_y + x, colour);
                        if (y != 0) {
                            putPixel(center_x + y, center_y - x, colour);
                            putPixel(center_x - y, center_y - x, colour);
                        }
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
        /// Draws a shimmer circle for utility shields with performance-optimised LUT lookup
        pub fn drawShimmerCircle(center_x: i32, center_y: i32, radius: i32, colour: Colour, offset: usize) void {
            if (radius < 0) return;
            if (radius == 0) {
                var count: usize = offset;
                shimmerPutPixel(center_x, center_y, colour, &count);
                return;
            }
            
            var x: i32 = radius;
            var y: i32 = 0;
            var err: i32 = 0;
            var count: usize = offset;

            while (x >= y) {
                shimmerPutPixel(center_x + x, center_y + y, colour, &count);
                shimmerPutPixel(center_x - x, center_y + y, colour, &count);
                if (y != 0) {
                    shimmerPutPixel(center_x + x, center_y - y, colour, &count);
                    shimmerPutPixel(center_x - x, center_y - y, colour, &count);
                }
                if (x != y) {
                    shimmerPutPixel(center_x + y, center_y + x, colour, &count);
                    shimmerPutPixel(center_x - y, center_y + x, colour, &count);
                    if (y != 0) {
                        shimmerPutPixel(center_x + y, center_y - x, colour, &count);
                        shimmerPutPixel(center_x - y, center_y - x, colour, &count);
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
        fn shimmerPutPixel(x: i32, y: i32, colour: Colour, count: *usize) void {
            const val = shimmer_lut[count.* & (shimmer_lut_size - 1)];
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
        pub fn fillCircle(center_x: i32, center_y: i32, radius: i32, colour: Colour) void {
            if (radius < 0) return;
            const r2 = radius * radius;
            var dy: i32 = 0;
            var dx: i32 = radius;
            
            while (dy <= radius) : (dy += 1) {
                while (dx * dx + dy * dy > r2) {
                    dx -= 1;
                }
                drawHLine(center_x - dx, center_x + dx, center_y + dy, colour);
                if (dy != 0) {
                    drawHLine(center_x - dx, center_x + dx, center_y - dy, colour);
                }
            }
        }

        // --------------------------------------------------------------------------------------------
        /// Clears the screen with a specific colour
        pub fn clear(colour: Colour) void {
            @memset(pixels, colour);
        }
    };
}
