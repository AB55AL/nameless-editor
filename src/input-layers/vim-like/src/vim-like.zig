const std = @import("std");
const print = std.debug.print;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const input_layer_main = @import("main.zig");
const core = @import("core");
const editor = core.editor;
const input = core.input;
const Key = input.Key;
const cif = core.common_input_functions;

pub const Mode = enum {
    normal,
    insert,
    visual,
    LEN,
};

pub const MappingFunctions = struct {
    ft_function: ?input.MappingSystem.FunctionType = null,
    default_ft_function: ?input.MappingSystem.FunctionType = null,
};

pub const state = struct {
    pub var mode: Mode = .normal;
    pub var mappings: [@enumToInt(Mode.LEN)]input.MappingSystem = undefined;
    pub var keys = std.BoundedArray(Key, 100).init(0) catch unreachable;
};

fn setMode(mode: Mode) void {
    state.mode = mode;
}

pub fn getMapping(mode: Mode) *core.input.MappingSystem {
    return &state.mappings[@enumToInt(mode)];
}

pub fn putFunction(mode: Mode, file_type: []const u8, keys: []const Key, function: input.MappingSystem.FunctionType, override_mapping: bool) !void {
    try getMapping(mode).put(file_type, keys, function, override_mapping);
}

pub fn getModeFunctions(mode: Mode, file_type: []const u8, keys: []const Key) MappingFunctions {
    var mapping = getMapping(mode);

    var mapping_functions = MappingFunctions{
        .ft_function = mapping.get(file_type, keys),
        .default_ft_function = mapping.get("", keys),
    };

    // TODO: Don's forget to ask if i need to wait for more keys
    if (!mapping.arePrefixKeys(file_type, keys) and !mapping.arePrefixKeys("", keys))
        state.keys.len = 0;

    return mapping_functions;
}

////////////////////////////////////////////////////////////////////////////////
// Function wrappers
////////////////////////////////////////////////////////////////////////////////
pub fn setNormalMode() void {
    setMode(.normal);
}
pub fn setInsertMode() void {
    setMode(.insert);
}
pub fn setVisualMode() void {
    setMode(.visual);
}

pub fn openCommandLine() void {
    setMode(.insert);
    core.command_line.open();
}

pub fn closeCommandLine() void {
    setMode(.normal);
    core.command_line.close();
}

pub fn enterKey() void {
    if (editor.command_line_is_open) {
        core.command_line.run() catch |err| {
            print("Couldn't run command. err={}\n", .{err});
        };
        setMode(.normal);
    } else insertNewLineAtCursor();
}

pub fn insertNewLineAtCursor() void {
    input_layer_main.characterInput("\n");
}

pub fn moveForward() void {
    const d = core.motions.white_space;
    var fbw = core.ui.focused_buffer_window orelse return;
    const range = core.motions.forward(fbw.data.buffer, &d) orelse return;
    fbw.data.buffer.cursor_index = range.endPreviousCP(fbw.data.buffer);
}

pub fn moveBackwards() void {
    const d = core.motions.white_space;
    var fbw = core.ui.focused_buffer_window orelse return;
    const range = core.motions.backward(fbw.data.buffer, &d) orelse return;
    fbw.data.buffer.cursor_index = range.start;
}

pub fn paste() void {
    var fb = core.focusedBuffer() orelse return;
    _ = fb;

    // var clipboard = glfw.getClipboardString() orelse {
    //     core.notify("Clipboard", "Empty", 2000);
    //     return;
    // };
    // fb.insertBeforeCursor(clipboard) catch |err| {
    //     print("input_layer.paste()\n\t{}\n", .{err});
    // };
}

pub fn randomInsertions() void {
    var fbw = core.ui.focused_buffer_window orelse return;

    var i: u32 = 0;
    while (i < 1000) : (i += 1) {
        const new_cursor = std.crypto.random.int(u64) % fbw.data.buffer.lineCount();
        fbw.data.buffer.cursor_index = new_cursor;
        fbw.data.buffer.insertBeforeCursor("st") catch |err| {
            print("{}\n", .{err});
        };
        // fbw.setWindowCursorToBuffer();
    }
}
