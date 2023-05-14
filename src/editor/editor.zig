const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const assert = std.debug.assert;
const file_io = @import("file_io.zig");

const ts = @cImport(@cInclude("tree_sitter/api.h"));

const globals = @import("../core.zig").globals;

const buffer_ui = @import("buffer_window.zig");
const BufferWindow = buffer_ui.BufferWindow;
const Dir = BufferWindow.Dir;
const BufferWindowNode = buffer_ui.BufferWindowNode;
const command_line = @import("command_line.zig");

const ui_api = @import("../ui/ui.zig");

const utils = @import("../utils.zig");

const editor = globals.editor;
const internal = globals.internal;

////////////////////////////////////////////////////////////////////////////////
// The File is divides into 3 sections.
// Section 1: Error and Struct definitions
// Section 2: Functions that do all the work
// Section 3: Convenience functions that wrap functions in Section 2
////////////////////////////////////////////////////////////////////////////////

////////////////////////////////////////////////////////////////////////////////
// Section 1: Error and Struct definitions
////////////////////////////////////////////////////////////////////////////////

pub const KeyQueue = std.BoundedArray(input.Key, 1024);
pub const CharQueue = std.BoundedArray(u21, 1024);

pub const Buffer = @import("buffer.zig");
pub const input = @import("input.zig");
pub const common_input_functions = @import("common_input_functions.zig");
pub const registers = @import("registers.zig");
pub const hooks = @import("hooks.zig");
pub const TreeSitterData = @import("tree_sitter.zig").TreeSitterData;
pub usingnamespace @import("buffer_window.zig");

pub const Error = error{
    SavingPathlessBuffer,
    KillingDirtyBuffer,
};

pub const BufferWindowOptions = struct {
    dir: ?BufferWindow.Dir = null,
    first_visiable_row: u64 = 1,
    percent: f32 = 0.5,
};

pub const SaveOptions = struct { force_save: bool = false };

pub const KillOptions = struct { force_kill: bool = false };

pub const BufferHandle = struct { handle: u32 };

////////////////////////////////////////////////////////////////////////////////
// Section 2: Functions that do all the work
////////////////////////////////////////////////////////////////////////////////

pub fn generateHandle() BufferHandle {
    const static = struct {
        var handle: u32 = 0;
    };

    const h = static.handle;
    static.handle += 1;
    return .{ .handle = h };
}

/// Returns a handle to a buffer
/// Creates a Buffer and returns a BufferHandle to it
pub fn createBuffer(file_path: []const u8) !BufferHandle {
    if (try getBufferFP(file_path)) |handle| return handle;

    try editor.buffers.ensureUnusedCapacity(internal.allocator, 1);
    const handle = generateHandle();
    var buffer = try createLocalBuffer(file_path, handle);
    editor.buffers.putAssumeCapacity(handle, buffer);

    var buffer_ptr = editor.buffers.getPtr(handle).?;
    editor.hooks.dispatch(.buffer_created, .{ buffer_ptr, handle });
    return handle;
}

/// Opens a file and returns a Buffer.
/// Does not add the buffer to the editor.buffers hashmap
/// Always creates a new buffer
pub fn createLocalBuffer(file_path: []const u8, bhandle: ?BufferHandle) !Buffer {
    var buffer: Buffer = undefined;

    if (file_path.len > 0) {
        var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
        const full_file_path = try file_io.fullFilePath(file_path, &out_buffer);

        const file = try fs.cwd().openFile(full_file_path, .{});
        defer file.close();
        const metadata = try file.metadata();
        const perms = metadata.permissions();
        try file.seekTo(0);
        var buf = try file.readToEndAlloc(internal.allocator, metadata.size());
        defer internal.allocator.free(buf);

        buffer = try Buffer.init(internal.allocator, full_file_path, buf, bhandle);
        buffer.metadata.file_last_mod_time = metadata.modified();
        buffer.metadata.read_only = perms.readOnly();
    } else {
        buffer = try Buffer.init(internal.allocator, "", "", bhandle);
    }

    return buffer;
}

pub fn getBuffer(self: BufferHandle) ?*Buffer {
    return editor.buffers.getPtr(self);
}

/// Given a *file_path* searches the editor.buffers hashmap and returns a BufferHandle
pub fn getBufferFP(file_path: []const u8) !?BufferHandle {
    var out_path_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const full_fp = try file_io.fullFilePath(file_path, &out_path_buffer);

    var iter = editor.buffers.iterator();
    while (iter.next()) |kv| {
        const buffer_fp = kv.value_ptr.metadata.file_path;
        if (std.mem.eql(u8, full_fp, buffer_fp))
            return kv.key_ptr.*; // handle
    }

    return null;
}

pub fn openBufferH(bhandle: BufferHandle, bw_opts: BufferWindowOptions) !void {
    if (bhandle.getBuffer() == null) return;

    var prev_fbw = focusedBW();
    try newFocusedBW(bhandle, bw_opts);
    if (prev_fbw) |fbw| pushAsPreviousBW(fbw);
}

pub fn openBufferFP(file_path: []const u8, bw_opts: BufferWindowOptions) !BufferHandle {
    const bhandle = try createBuffer(file_path);
    var prev_fbw = focusedBW();
    try newFocusedBW(bhandle, bw_opts);
    if (prev_fbw) |fbw| pushAsPreviousBW(fbw);
    return bhandle;
}

pub fn saveBuffer(bhandle: BufferHandle, options: SaveOptions) !void {
    var buffer = getBuffer(bhandle) orelse return;

    if (buffer.metadata.file_path.len == 0)
        return Error.SavingPathlessBuffer;

    try file_io.writeToFile(buffer, options.force_save);
    buffer.metadata.dirty = false;
}

pub fn killBuffer(bhandle: BufferHandle, options: KillOptions) !void {
    var buffer = bhandle.getBuffer() orelse return;

    if (!options.force_kill and buffer.metadata.dirty)
        return Error.KillingDirtyBuffer;

    buffer.deinitNoDestroy();
    _ = globals.editor.buffers.remove(bhandle);
}

pub fn closeBW(buffer_window: *BufferWindowNode) void {
    editor.focused_buffer_window = popPreviousBW();

    // set the last child's dir so that it can take over the free space left by the parent
    if (buffer_window.lastChild()) |lc|
        lc.data.dir = buffer_window.data.dir;

    editor.visiable_buffers_tree.removePromoteLast(buffer_window);

    // delete all occurrences of the buffer window pointer
    for (editor.previous_focused_buffer_wins.slice(), 0..) |bw, i| {
        if (bw == buffer_window)
            _ = editor.previous_focused_buffer_wins.orderedRemove(i);
    }

    buffer_window.data.deinit();
    internal.allocator.destroy(buffer_window);
}

pub fn newFocusedBW(bhandle: BufferHandle, options: BufferWindowOptions) !void {
    if (options.dir == null and focusedBW() != null) {
        focusedBW().?.data.bhandle = bhandle;
        return;
    }

    var new_node = try globals.internal.allocator.create(BufferWindowNode);
    new_node.* = .{
        .data = try BufferWindow.init(
            bhandle,
            options.first_visiable_row,
            options.dir orelse .north,
            options.percent,
        ),
    };

    if (focusedBW()) |fbw| {
        fbw.appendChild(new_node);
    } else if (editor.visiable_buffers_tree.root == null) {
        editor.visiable_buffers_tree.root = new_node;
    }

    editor.focused_buffer_window = new_node;
}

pub fn setFocusedBW(buffer_window: *BufferWindowNode) void {
    if (buffer_window == cliBW()) return;

    if (focusedBW()) |fbw|
        pushAsPreviousBW(fbw);

    editor.focused_buffer_window = buffer_window;

    if (buffer_window != cliBW()) closeCLI(false, true);
}

pub fn focusedBW() ?*BufferWindowNode {
    return globals.editor.focused_buffer_window;
}

pub fn pushAsPreviousBW(buffer_win: *BufferWindowNode) void {
    if (buffer_win == cliBW()) return;

    var wins = &globals.editor.previous_focused_buffer_wins;
    wins.append(buffer_win) catch {
        _ = wins.orderedRemove(0);
        wins.append(buffer_win) catch unreachable;
    };
}

pub fn popPreviousBW() ?*BufferWindowNode {
    var wins = &globals.editor.previous_focused_buffer_wins;

    while (wins.len != 0) {
        var buffer_win = wins.popOrNull();
        if (buffer_win != null and buffer_win.? != cliBW())
            return buffer_win.?;
    }

    return null;
}

////////////////////////////////////////////////////////////////////////////////
// CLI functions

pub fn cliBuffer() *Buffer {
    return getBuffer(cliBW().data.bhandle).?;
}

pub fn cliBW() *BufferWindowNode {
    return &globals.editor.cli.buffer_window;
}

pub fn cliIsOpen() bool {
    return globals.editor.cli.open;
}
pub fn openCLI() void {
    globals.editor.cli.open = true;
    if (focusedBW()) |fbw| pushAsPreviousBW(fbw);
    globals.editor.focused_buffer_window = cliBW();
}

pub fn closeCLI(pop_previous_window: bool, focus_buffers: bool) void {
    globals.editor.cli.open = false;
    cliBuffer().clear() catch |err| {
        print("cloudn't clear command_line buffer err={}", .{err});
    };

    if (pop_previous_window) globals.editor.focused_buffer_window = popPreviousBW();
    if (focus_buffers) globals.ui.focus_buffers = true;
}

pub fn runCLI() void {
    var cli_buffer = cliBuffer();
    var command_str: [4096]u8 = undefined;
    var len = cli_buffer.size();

    const command_line_content = cli_buffer.getAllLines(internal.allocator) catch return;
    defer internal.allocator.free(command_line_content);
    std.mem.copy(u8, &command_str, command_line_content);

    closeCLI(true, true);
    globals.editor.cli.run(internal.allocator, command_str[0 .. len - 1]) catch |err| {
        ui_api.notify("Command Line Error:", .{}, "{!}", .{err}, 3);
    };
}

pub fn addCommand(command: []const u8, comptime fn_ptr: anytype, description: []const u8) !void {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;
    if (fn_info.return_type.? != void)
        @compileError("The command's function return type needs to be void");
    if (fn_info.is_var_args)
        @compileError("The command's function cannot be variadic");

    if (command.len == 0) return error.EmptyCommand;
    if (std.mem.count(u8, command, " ") > 0) return error.CommandContainsSpaces;

    const cmd_string = try stringStorageGetOrPut(command);
    const desc_string = try stringStorageGetOrPut(description);

    try globals.editor.cli.functions.put(cmd_string, .{
        .function = command_line.beholdMyFunctionInator(fn_ptr).funcy,
        .description = desc_string,
    });
}

////////////////////////////////////////////////////////////////////////////////
// String Storage

pub fn stringStorageGetOrPut(string: []const u8) ![]const u8 {
    var gop = try editor.string_storage.getOrPut(string);
    if (!gop.found_existing) gop.key_ptr.* = try utils.newSlice(editor.string_storage.allocator, string);
    return gop.key_ptr.*;
}

////////////////////////////////////////////////////////////////////////////////
// Tree Sitter

/// A wrapper around the global TreeSitterData. This wrapper ensures that all key and value string are valid at all times.
pub const tree_sitter = struct {
    pub fn putParser(file_type: []const u8, parser: *TreeSitterData.Parser) !void {
        var self = getTS();
        const ft = try stringStorageGetOrPut(file_type);
        try self.parsers.put(self.allocator, ft, parser);
    }

    pub fn getParser(file_type: []const u8) ?*TreeSitterData.Parser {
        var self = getTS();
        return self.parsers.get(file_type);
    }

    pub fn putQuery(file_type: []const u8, query_name: []const u8, query_data: TreeSitterData.QueryData) !void {
        var self = getTS();
        const ft = try stringStorageGetOrPut(file_type);
        const qn = try stringStorageGetOrPut(query_name);
        try self.queries.put(self.allocator, ft, qn, query_data);
    }

    pub fn getQuery(file_type: []const u8, query_name: []const u8) ?TreeSitterData.QueryData {
        var self = getTS();
        return self.queries.get(file_type, query_name);
    }

    pub fn putTree(bhandle: BufferHandle, tree: *TreeSitterData.Tree) !void {
        var self = getTS();
        try self.trees.put(self.allocator, bhandle, tree);
    }

    pub fn getTree(bhandle: BufferHandle) ?*TreeSitterData.Tree {
        var self = getTS();
        return self.trees.get(bhandle);
    }

    pub fn putTheme(file_type: []const u8, theme_name: []const u8, theme: []TreeSitterData.CaptureColor) !void {
        var self = getTS();
        const ft = try stringStorageGetOrPut(file_type);
        const tn = try stringStorageGetOrPut(theme_name);

        var theme_copy = TreeSitterData.ThemeMap{};
        errdefer theme_copy.deinit(self.allocator);
        for (theme) |cc| {
            const ts_capture_name = try stringStorageGetOrPut(cc.name);
            try theme_copy.put(self.allocator, ts_capture_name, cc.color);
        }
        try self.themes.put(self.allocator, ft, tn, theme_copy);
    }

    pub fn getTheme(file_type: []const u8, theme_name: []const u8) ?*TreeSitterData.ThemeMap {
        var self = getTS();
        return self.themes.data.getPtr(.{ file_type, theme_name });
    }

    pub fn getActiveTheme(file_type: []const u8) ?[]const u8 {
        var self = getTS();
        return self.active_themes.get(file_type);
    }

    pub fn setActiveTheme(file_type: []const u8, theme_name: []const u8) !void {
        var self = getTS();
        const theme_exits = self.themes.data.getKey(.{ file_type, theme_name }) != null;
        if (theme_exits) {
            const ft = try stringStorageGetOrPut(file_type);
            const tn = try stringStorageGetOrPut(theme_name);
            try self.active_themes.put(self.allocator, ft, tn);
        }
    }
};

pub fn getTS() *TreeSitterData {
    return &globals.editor.tree_sitter;
}

pub fn getTSLang(lang: []const u8) ?*ts.TSLanguage {
    return globals.editor.ts_langs.get(lang);
}

////////////////////////////////////////////////////////////////////////////////
// Section 3: Convenience functions that wrap functions in Section 2
////////////////////////////////////////////////////////////////////////////////
pub fn focusedBuffer() ?*Buffer {
    return getBuffer(focusedBufferHandle() orelse return null);
}

pub fn focusedBufferAndHandle() ?struct { bhandle: BufferHandle, buffer: *Buffer } {
    var bhandle = focusedBufferHandle() orelse return null;
    return .{ .bhandle = bhandle, .buffer = getBuffer(bhandle) orelse return null };
}

pub fn focusedBufferAndBW() ?struct { buffer: *Buffer, bw: *BufferWindowNode } {
    var bw = focusedBW() orelse return null;
    return .{ .bw = bw, .buffer = getBuffer(bw.data.bhandle) orelse return null };
}

pub fn focusedBufferHandle() ?BufferHandle {
    return (focusedBW() orelse return null).data.bhandle;
}
