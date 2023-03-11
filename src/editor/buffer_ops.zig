const std = @import("std");
const print = std.debug.print;
const fs = std.fs;
const ArrayList = std.ArrayList;
const eql = std.mem.eql;
const assert = std.debug.assert;
const Buffer = @import("buffer.zig");
const file_io = @import("file_io.zig");

const globals = @import("../core.zig").globals;

const buffer_ui = @import("../ui/buffer.zig");
const BufferWindow = buffer_ui.BufferWindow;
const Dir = BufferWindow.Dir;

const editor = globals.editor;
const ui = globals.ui;
const internal = globals.internal;

pub const Error = error{
    SavingPathlessBuffer,
    SavingInvalidBuffer,
    KillingInvalidBuffer,
    KillingDirtyBuffer,
};

/// Returns a pointer to a buffer.
/// If a buffer with the given file_path already exists
/// returns a pointer to that buffer otherwise
/// creates a new buffer, adds it to the editor.buffers list and
/// returns a pointer to it.
pub fn createBuffer(file_path: []const u8) !*Buffer {
    if (file_path.len > 0) {
        var buf = try getBufferFP(file_path);
        if (buf) |b| return b;
    }

    var buffer = try createLocalBuffer(file_path);

    // Prepend to linked list
    buffer.next_buffer = editor.first_buffer;
    editor.first_buffer = buffer;
    editor.valid_buffers_count += 1;

    return buffer;
}

/// Opens a file and returns a pointer to a buffer.
/// Does not add the buffer to the editor.buffers array
/// Always creates a new buffer
pub fn createLocalBuffer(file_path: []const u8) !*Buffer {
    var buffer = try internal.allocator.create(Buffer);
    errdefer internal.allocator.destroy(buffer);

    if (file_path.len > 0) {
        var out_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
        const full_file_path = try file_io.fullFilePath(file_path, &out_buffer);

        const file = try fs.cwd().openFile(full_file_path, .{});
        defer file.close();
        const metadata = try file.metadata();
        try file.seekTo(0);
        var buf = try file.readToEndAlloc(internal.allocator, metadata.size());
        defer internal.allocator.free(buf);

        buffer.* = try Buffer.init(internal.allocator, full_file_path, buf);
        buffer.metadata.file_last_mod_time = metadata.modified();
    } else {
        buffer.* = try Buffer.init(internal.allocator, "", "");
    }

    return buffer;
}

pub fn createPathLessBuffer() !*Buffer {
    var buffer = try internal.allocator.create(Buffer);
    buffer.* = try Buffer.init(globals.internal.allocator, "", "");

    // Prepend to linked list
    buffer.next_buffer = editor.first_buffer;
    editor.first_buffer = buffer;
    editor.valid_buffers_count += 1;

    return buffer;
}

/// Given an *index* searches the editor.buffers array for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferI(index: u32) ?*Buffer {
    if (editor.first_buffer == null) return null;

    var buffer = editor.first_buffer.?;
    while (true) {
        if (buffer.state == .valid and buffer.index == index) {
            return buffer;
        } else if (buffer.next_buffer) |nb| {
            buffer = nb;
        } else {
            return null;
        }
    }
}

fn getOrCreateBuffer(index: ?u32, file_path: []const u8) !*Buffer {
    var buffer: *Buffer = undefined;
    if (index) |i|
        buffer = getBufferI(i) orelse
            try getBufferFP(file_path) orelse
            try createBuffer(file_path)
    else
        buffer = (try getBufferFP(file_path)) orelse
            try createBuffer(file_path);

    return buffer;
}

/// Given an *file_path* searches the valid buffer list for a buffer
/// matching either.
/// Returns null if the buffer isn't found.
pub fn getBufferFP(file_path: []const u8) !?*Buffer {
    if (editor.first_buffer == null) return null;

    var buffer = editor.first_buffer.?;
    var out_path_buffer: [fs.MAX_PATH_BYTES]u8 = undefined;
    const full_fp = try file_io.fullFilePath(file_path, &out_path_buffer);
    while (true) {
        if (eql(u8, full_fp, buffer.metadata.file_path)) {
            return buffer;
        }

        buffer = buffer.next_buffer orelse return null;
        while (buffer.state == .invalid)
            buffer = buffer.next_buffer orelse return null;
    }
    return null;
}

pub fn openBufferI(index: u32, dir: ?Dir) !*Buffer {
    var buffer: *Buffer = try getOrCreateBuffer(index, "");
    if (ui.focused_buffer_window) |fbw|
        pushAsPreviousBufferWindow(fbw);

    try newBufferWindow(buffer, dir);
    return buffer;
}

pub fn openBufferFP(file_path: []const u8, dir: ?Dir) !*Buffer {
    var buffer: *Buffer = try getOrCreateBuffer(null, file_path);
    if (ui.focused_buffer_window) |fbw|
        pushAsPreviousBufferWindow(fbw);

    try newBufferWindow(buffer, dir);
    return buffer;
}

pub fn saveBuffer(buffer: *Buffer, force_write: bool) !void {
    if (buffer.metadata.file_path.len == 0)
        return Error.SavingPathlessBuffer;
    if (buffer.state == .invalid)
        return Error.SavingInvalidBuffer;

    try file_io.writeToFile(buffer, force_write);
    buffer.metadata.dirty = false;
}

/// Deinits the buffer and closes it's window.
/// To only deinit see `Buffer.deinitNoDestroy()` or `Buffer.deinitAndDestroy()`
pub fn killBuffer(buffer: *Buffer) !void {
    if (buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    if (buffer.metadata.dirty)
        return Error.KillingDirtyBuffer;

    try forceKillBuffer(buffer);
}

pub fn forceKillBuffer(buffer: *Buffer) !void {
    if (buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    buffer.deinitNoDestroy();

    editor.valid_buffers_count -= 1;
}

pub fn saveAndQuit(buffer: *Buffer, force_write: bool) !void {
    try saveBuffer(buffer, force_write);
    try killBuffer(buffer);
}

pub fn killBufferWindow(buffer_window: *BufferWindow) !void {
    if (buffer_window.buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    if (buffer_window.buffer.metadata.dirty)
        return Error.KillingDirtyBuffer;

    try forceKillBufferWindow(buffer_window);
}

pub fn forceKillBufferWindow(buffer_window: *BufferWindow) !void {
    if (buffer_window.buffer.state == .invalid)
        return Error.KillingInvalidBuffer;

    if (windowCountWithBuffer(buffer_window.buffer) == 1) {
        try forceKillBuffer(buffer_window.buffer);
    }

    // Deleting the root node
    if (buffer_window == ui.visiable_buffers_tree and ui.visiable_buffers_tree.?.first_child != null) {
        var last_child = ui.visiable_buffers_tree.?.first_child.?.lastSibling();
        ui.visiable_buffers_tree = last_child;
        last_child.parent = null;

        var node = ui.visiable_buffers_tree.?.first_child;
        while (node != null and node != last_child) {
            node.?.parent = last_child;
        }
    } else if (ui.visiable_buffers_tree.?.first_child == null) {
        ui.visiable_buffers_tree = null;
    }

    deleteFromPreviousFocusedWindows(buffer_window);
    buffer_window.remove();
    internal.allocator.destroy(buffer_window);
    ui.focused_buffer_window = popPreviousFocusedBufferWindow();
}

pub fn saveAndQuitWindow(buffer_window: *BufferWindow, force_write: bool) !void {
    try saveBuffer(buffer_window.buffer, force_write);
    try killBufferWindow(buffer_window);
}

pub fn popPreviousFocusedBufferWindow() ?*BufferWindow {
    var wins = &globals.ui.previous_focused_buffer_wins;

    while (wins.len != 0) {
        var buffer_win = wins.popOrNull();
        if (buffer_win != null and buffer_win.?.buffer.state == .valid and buffer_win.? != &ui.command_line_buffer_window)
            return buffer_win.?;
    }

    return null;
}

pub fn pushAsPreviousBufferWindow(buffer_win: *BufferWindow) void {
    if (buffer_win == &ui.command_line_buffer_window) return;

    var wins = &globals.ui.previous_focused_buffer_wins;
    wins.append(buffer_win) catch {
        _ = wins.orderedRemove(0);
        wins.append(buffer_win) catch unreachable;
    };
}

pub fn focusedBuffer() ?*Buffer {
    return (globals.ui.focused_buffer_window orelse return null).buffer;
}

pub fn focusedBW() ?*BufferWindow {
    return (globals.ui.focused_buffer_window orelse return null);
}

pub fn windowCountWithBuffer(buffer: *Buffer) u32 {
    var root = ui.visiable_buffers_tree orelse return 0;
    // TODO: Don't allocate
    var array = root.treeToArray(internal.allocator) catch unreachable;
    defer internal.allocator.free(array);

    var count: u32 = 0;
    for (array) |win| {
        if (win.buffer.state == .valid and win.buffer.index == buffer.index)
            count += 1;
    }

    return count;
}

pub fn newBufferWindow(buffer: *Buffer, dir: ?BufferWindow.Dir) !void {
    if (ui.focused_buffer_window) |fbw| {
        if (dir) |d| {
            var bw = try fbw.addChild(globals.internal.allocator, buffer, 1, 0.5, d);
            ui.focused_buffer_window = bw;
        } else fbw.buffer = buffer;
    } else if (ui.visiable_buffers_tree == null) {
        var bw = try globals.internal.allocator.create(BufferWindow);
        bw.* = .{
            .buffer = buffer,
            .first_visiable_row = 1,
            .dir = .north,
        };

        ui.visiable_buffers_tree = bw;
        ui.focused_buffer_window = bw;
    }
}

pub fn setFocusedWindow(buffer_window: *BufferWindow) void {
    if (buffer_window == &ui.command_line_buffer_window) return;
    if (buffer_window.buffer.state == .invalid) return;

    if (ui.focused_buffer_window) |fbw|
        pushAsPreviousBufferWindow(fbw);

    ui.focused_buffer_window = buffer_window;
}

fn deleteFromPreviousFocusedWindows(buffer_window: *BufferWindow) void {
    for (ui.previous_focused_buffer_wins.slice(), 0..) |bw, i| {
        if (bw == buffer_window) {
            _ = ui.previous_focused_buffer_wins.orderedRemove(i);
            break;
        }
    }
}
