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
const mapAll = context.mapAll;
const mapSome = context.mapSome;

pub var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
pub var allocator: std.mem.Allocator = undefined;
pub var arena: std.heap.ArenaAllocator = undefined;
pub var arena_allocator: std.mem.Allocator = undefined;

pub var log_file: fs.File = undefined;

pub fn keyInput(key: Key) void {
    var file_type = if (core.focusedBuffer()) |fb| fb.metadata.buffer_type else "";
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

    var f = core.focusedBufferAndBW() orelse return;
    const cursor = f.bw.data.cursor() orelse return;

    f.buffer.insertAt(cursor, utf8_seq) catch |err| {
        core.notify("Error:", .{}, "{!}", .{err}, 3);
        return;
    };

    f.bw.data.setCursor(cursor + utf8_seq.len);

    const end = log_file.getEndPos() catch return;
    const insert = "insert:";
    _ = log_file.pwrite(insert, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite(utf8_seq, end + insert.len) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + insert.len + utf8_seq.len) catch |err| print("err={}", .{err});
}

pub fn setDefaultMappnigs() void {
    const f = input.functionKey;
    const a = input.asciiKey;
    map(.normal, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.insert, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.visual, &.{f(.none, .escape)}, vim_like.setNormalMode);

    setDefaultMappnigsNormalMode();
    setDefaultMappnigsInsertMode();
    setDefaultMappnigsVisualMode();

    mapAll(&.{f(.none, .f1)}, core.toggleBuffersUI);

    mapSome(&.{ .normal, .visual }, &.{a(.none, .h)}, vim_like.moveLeft);
    mapSome(&.{ .normal, .visual }, &.{a(.none, .j)}, vim_like.moveDown);
    mapSome(&.{ .normal, .visual }, &.{a(.none, .k)}, vim_like.moveUp);
    mapSome(&.{ .normal, .visual }, &.{a(.none, .l)}, vim_like.moveRight);
    mapSome(&.{ .normal, .visual }, &.{a(.none, .w)}, vim_like.moveForward);
    mapSome(&.{ .normal, .visual }, &.{a(.none, .b)}, vim_like.moveBackwards);

    mapAll(&.{f(.none, .page_up)}, scrollUp);
    mapAll(&.{f(.none, .page_down)}, scrollDown);
}

pub fn setDefaultMappnigsNormalMode() void {
    const f = input.functionKey;
    _ = f;
    const a = input.asciiKey;
    map(.normal, &.{a(.shift, .semicolon)}, vim_like.openCommandLine);

    map(.normal, &.{a(.none, .i)}, vim_like.setInsertMode);
    map(.normal, &.{a(.none, .v)}, vim_like.setVisualMode);
}

fn setDefaultMappnigsInsertMode() void {
    const f = input.functionKey;
    const a = input.asciiKey;

    map(.insert, &.{f(.none, .enter)}, vim_like.enterKey);
    map(.insert, &.{f(.none, .backspace)}, cif.deleteBackward);
    map(.insert, &.{f(.none, .delete)}, cif.deleteForward);

    map(.insert, &.{a(.control, .v)}, vim_like.paste);
}

fn setDefaultMappnigsVisualMode() void {
    const f = input.functionKey;
    const a = input.asciiKey;
    _ = f;
    _ = a;
}

fn logKey(key: Key) void {
    const end = log_file.getEndPos() catch return;
    var out: [20]u8 = undefined;
    var key_str = key.toString(&out);

    _ = log_file.pwrite(key_str, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + key_str.len) catch |err| print("err={}", .{err});
}

fn scrollUp() void {
    var fbw = core.focusedBW() orelse return;
    fbw.data.scrollUp(1);
}

fn scrollDown() void {
    var fbw = core.focusedBW() orelse return;
    fbw.data.scrollDown(1);
}
