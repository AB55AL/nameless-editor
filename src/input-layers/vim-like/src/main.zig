const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const fs = std.fs;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const glfw = @import("glfw");
const imgui = @import("imgui");

const core = @import("core");
const editor = core.editor;
const input = core.input;
const cif = core.common_input_functions;
const Key = input.Key;

const vim_like = @import("vim-like.zig");
const context = @import("context.zig");
const map = context.map;

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var arena: std.heap.ArenaAllocator = undefined;
pub var arena_allocator: std.mem.Allocator = undefined;

pub var log_file: fs.File = undefined;

pub fn keyInput(key: Key) void {
    var file_type = if (core.focusedBuffer()) |fb| fb.metadata.file_type else "";
    vim_like.state.keys.append(key) catch {
        vim_like.state.keys.len = 0;
        return;
    }; // TODO: Notify user then clear array

    logKey(key);
    const functions = vim_like.getModeFunctions(vim_like.state.mode, file_type, vim_like.state.keys.slice());
    const f = functions.ft_function orelse functions.default_ft_function orelse return;
    f();
}

pub fn characterInput(utf8_seq: []const u8) void {
    if (vim_like.state.mode != .insert) return;

    var fb = core.focusedBuffer() orelse return;
    fb.insertBeforeCursor(utf8_seq) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };

    if (core.editor.command_line_is_open and core.editor.command_line_buffer.lines.byteAt(0) == ':') {
        fb.clear() catch unreachable;
        return;
    }

    // var focused_buffer_window = core.ui.focused_buffer_window orelse return;
    // focused_buffer_window.setWindowCursorToBuffer();
    // focused_buffer_window.buffer.resetSelection();

    const end = log_file.getEndPos() catch return;
    const insert = "insert:";
    _ = log_file.pwrite(insert, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite(utf8_seq, end + insert.len) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + insert.len + utf8_seq.len) catch |err| print("err={}", .{err});
}

pub fn setDefaultMappnigs() void {
    const f = input.functionKey;
    map(.normal, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.insert, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.visual, &.{f(.none, .escape)}, vim_like.setNormalMode);

    setDefaultMappnigsNormalMode();
    setDefaultMappnigsInsertMode();
    setDefaultMappnigsVisualMode();
}

pub fn setDefaultMappnigsNormalMode() void {
    const f = input.functionKey;
    const a = input.asciiKey;
    map(.normal, &.{a(.shift, .semicolon)}, vim_like.openCommandLine);

    map(.normal, &.{a(.none, .i)}, vim_like.setInsertMode);
    map(.normal, &.{a(.control, .i)}, vim_like.setInsertMode);
    map(.normal, &.{a(.none, .v)}, vim_like.setVisualMode);

    map(.normal, &.{a(.none, .h)}, cif.moveLeft);
    map(.normal, &.{a(.none, .j)}, cif.moveDown);
    map(.normal, &.{a(.none, .k)}, cif.moveUp);
    map(.normal, &.{a(.none, .l)}, cif.moveRight);

    map(.normal, &.{a(.none, .w)}, vim_like.moveForward);
    map(.normal, &.{a(.none, .b)}, vim_like.moveBackwards);

    map(.normal, &.{f(.none, .f5)}, vim_like.randomInsertions);

    map(.normal, &.{f(.none, .page_up)}, scrollUp);
    map(.normal, &.{f(.none, .page_down)}, scrollDown);
}

fn scrollUp() void {
    var fbw = core.focusedBW() orelse return;
    fbw.data.scrollUp(1);
}

fn scrollDown() void {
    var fbw = core.focusedBW() orelse return;
    fbw.data.scrollDown(1);
}

fn setDefaultMappnigsInsertMode() void {
    const f = input.functionKey;
    const a = input.asciiKey;

    map(.insert, &.{f(.none, .enter)}, vim_like.enterKey);
    map(.insert, &.{f(.none, .backspace)}, cif.deleteBackward);
    map(.insert, &.{f(.none, .delete)}, cif.deleteForward);

    map(.insert, &.{f(.none, .right)}, cif.moveRight);
    map(.insert, &.{f(.none, .left)}, cif.moveLeft);
    map(.insert, &.{f(.none, .up)}, cif.moveUp);
    map(.insert, &.{f(.none, .down)}, cif.moveDown);

    map(.insert, &.{a(.control, .v)}, vim_like.paste);
}

fn setDefaultMappnigsVisualMode() void {}

fn logKey(key: Key) void {
    const end = log_file.getEndPos() catch return;
    var out: [20]u8 = undefined;
    var key_str = key.toString(&out);

    _ = log_file.pwrite(key_str, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + key_str.len) catch |err| print("err={}", .{err});
}
