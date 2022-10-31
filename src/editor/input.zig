const std = @import("std");
const print = std.debug.print;
const unicode = std.unicode;

pub const KeyUnion = union(enum) {
    code_point: u21,
    function_key: FunctionKey,
};
pub const Key = struct {
    key: KeyUnion,
    mod: Modifiers = .none,

    pub fn toString(key: Key, out: []u8) []u8 {
        std.debug.assert(out.len >= 6 + 14); // 6 for modifiers. 14 for function_key maximum length

        var size: u16 = 0;
        const mod_str = key.mod.toString();
        std.mem.copy(u8, out, mod_str);
        size += @intCast(u16, mod_str.len);

        switch (key.key) {
            .code_point => {
                const bytes = unicode.utf8Encode(key.key.code_point, out[mod_str.len..]) catch unreachable;
                size += bytes;
            },
            .function_key => {
                const function_key_str = key.key.function_key.toString();
                std.mem.copy(u8, out[mod_str.len..], function_key_str);
                size += @intCast(u16, function_key_str.len);
            },
        }

        return out[0..size];
    }
};

pub fn asciiKey(mod: Modifiers, key: Ascii) Key {
    return .{
        .key = .{ .code_point = @enumToInt(key) },
        .mod = mod,
    };
}

pub fn functionKey(mod: Modifiers, function_key: FunctionKey) Key {
    return .{
        .key = .{ .function_key = function_key },
        .mod = mod,
    };
}

pub fn codePoint(mod: Modifiers, code_point: u21) Key {
    return .{
        .key = .{ .code_point = code_point },
        .mod = mod,
    };
}

pub const Modifiers = enum(u3) {
    none = 0,
    shift = 1,
    control = 2,
    control_shift = 3,
    alt = 4,
    alt_shift = 5,
    control_alt = 6,
    control_alt_shift = 7,

    pub fn toString(mod: Modifiers) []const u8 {
        return switch (mod) {
            .none => "",
            .shift => "S_",
            .control => "C_",
            .control_shift => "C_S_",
            .alt => "A_",
            .alt_shift => "A_S_",
            .control_alt => "C_A_",
            .control_alt_shift => "C_S_A_",
        };
    }
};

pub const FunctionKey = enum(u7) {
    unknown = 1,
    space,
    escape,
    enter,
    tab,
    backspace,
    insert,
    delete,
    right,
    left,
    down,
    up,
    page_up,
    page_down,
    home,
    end,
    caps_lock,
    scroll_lock,
    num_lock,
    print_screen,
    pause,
    f1,
    f2,
    f3,
    f4,
    f5,
    f6,
    f7,
    f8,
    f9,
    f10,
    f11,
    f12,
    f13,
    f14,
    f15,
    f16,
    f17,
    f18,
    f19,
    f20,
    f21,
    f22,
    f23,
    f24,
    kp_enter,

    pub fn toString(key: FunctionKey) []const u8 {
        return switch (key) {
            .space => "<SPACE>",
            .escape => "<ESCAPE>",
            .enter => "<ENTER>",
            .tab => "<TAB>",
            .backspace => "<BACKSPACE>",
            .insert => "<INSERT>",
            .delete => "<DELETE>",
            .right => "<RIGHT>",
            .left => "<LEFT>",
            .down => "<DOWN>",
            .up => "<UP>",
            .page_up => "<PAGE_UP>",
            .page_down => "<PAGE_DOWN>",
            .home => "<HOME>",
            .end => "<END>",
            .caps_lock => "<CAPS_LOCK>",
            .scroll_lock => "<SCROLL_LOCK>",
            .num_lock => "<NUM_LOCK>",
            .print_screen => "<PRINT_SCREEN>",
            .pause => "<PAUSE>",
            .f1 => "<F1>",
            .f2 => "<F2>",
            .f3 => "<F3>",
            .f4 => "<F4>",
            .f5 => "<F5>",
            .f6 => "<F6>",
            .f7 => "<F7>",
            .f8 => "<F8>",
            .f9 => "<F9>",
            .f10 => "<F10>",
            .f11 => "<F11>",
            .f12 => "<F12>",
            .f13 => "<F13>",
            .f14 => "<F14>",
            .f15 => "<F15>",
            .f16 => "<F16>",
            .f17 => "<F17>",
            .f18 => "<F18>",
            .f19 => "<F19>",
            .f20 => "<F20>",
            .f21 => "<F21>",
            .f22 => "<F22>",
            .f23 => "<F23>",
            .f24 => "<F24>",
            .kp_enter => "<KP_ENTER>",
            .unknown => "UNKNOWN",
        };
    }
};

/// This enum has some ASCII characters the missing ones can be achieved by doing `shift+key`
pub const Ascii = enum(u8) {
    a = 97,
    b = 98,
    c = 99,
    d = 100,
    e = 101,
    f = 102,
    g = 103,
    h = 104,
    i = 105,
    j = 106,
    k = 107,
    l = 108,
    m = 109,
    n = 110,
    o = 111,
    p = 112,
    q = 113,
    r = 114,
    s = 115,
    t = 116,
    u = 117,
    v = 118,
    w = 119,
    x = 120,
    y = 121,
    z = 122,

    zero = 48,
    one = 49,
    two = 50,
    three = 51,
    four = 52,
    five = 53,
    six = 54,
    seven = 55,
    eight = 56,
    nine = 57,

    single_quote = 39,
    comma = 44,
    minus = 45,
    dot = 46,
    slash = 47,
    semicolon = 59,
    equal = 61,
    left_bracket = 91,
    backslash = 92,
    right_bracket = 93,
    backtick = 96,
};
