// ------------------------------------------------------------------------------------------------
// Standard definitions for software rendering operations
// ------------------------------------------------------------------------------------------------

pub const Colour = struct {
    r: u8,
    g: u8,
    b: u8,
    a: u8,

    pub const white = Colour{ .r = 255, .g = 255, .b = 255, .a = 255 };
    pub const black = Colour{ .r = 0, .g = 0, .b = 0, .a = 255 };
    pub const red = Colour{ .r = 255, .g = 0, .b = 0, .a = 255 };
    pub const green = Colour{ .r = 0, .g = 255, .b = 0, .a = 255 };
    pub const blue = Colour{ .r = 0, .g = 0, .b = 255, .a = 255 };
    pub const yellow = Colour{ .r = 255, .g = 255, .b = 0, .a = 255 };
    pub const cyan = Colour{ .r = 0, .g = 242, .b = 254, .a = 255 };
    pub const cyan_dim = Colour{ .r = 0, .g = 121, .b = 127, .a = 255 };

    pub fn rgba(r: u8, g: u8, b: u8, a: u8) Colour {
        return .{ .r = r, .g = g, .b = b, .a = a };
    }
};
