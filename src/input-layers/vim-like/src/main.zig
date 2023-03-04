const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const fs = std.fs;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;
const AutoHashMap = std.AutoHashMap;

const glfw = @import("glfw");

const core = @import("core");
const editor = core.editor;
const input = core.input;
const cif = core.common_input_functions;
const Key = input.Key;

const vim_like = @import("vim-like.zig");

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
var arena: std.heap.ArenaAllocator = undefined;
var arena_allocator: std.mem.Allocator = undefined;

var log_file: fs.File = undefined;

pub fn init() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
    arena = std.heap.ArenaAllocator.init(allocator);
    arena_allocator = arena.allocator();

    for (&vim_like.state.mappings) |*m| {
        m.* = core.input.MappingSystem.init(arena_allocator);
        _ = try m.addFileType(""); // Global and fallback file_type
    }
    setDefaultMappnigs();
    {
        const data_path = std.os.getenv("XDG_DATA_HOME") orelse return;
        const log_path = std.mem.concat(allocator, u8, &.{ data_path, "/ne" }) catch return;
        defer allocator.free(log_path);
        var dir = fs.openDirAbsolute(log_path, .{}) catch return;
        defer dir.close();

        log_file = (dir.openFile("input-log", .{ .mode = .write_only }) catch |err| if (err == fs.Dir.OpenError.FileNotFound)
            dir.createFile("input-log", .{})
        else
            err) catch return;

        const end = log_file.getEndPos() catch return;
        _ = log_file.pwrite("\n---------------new editor instance---------------\n", end) catch |err| print("err={}", .{err});
    }
}

pub fn deinit() void {
    arena.deinit(); // deinit the mappings

    log_file.close();
    _ = gpa.deinit();
}

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

pub fn map(mode: vim_like.Mode, keys: []const Key, function: core.input.MappingSystem.FunctionType) void {
    vim_like.putFunction(mode, "", keys, function, false) catch |err| {
        print("input_layer.map()\n\t", .{});
        switch (err) {
            error.OverridingFunction, error.OverridingPrefix => {
                print("{} The following keys have not been mapped as they override an existing mapping =>\t", .{err});
                var out: [Key.MAX_STRING_LEN]u8 = undefined;
                for (keys) |k| print("{s} ", .{k.toString(&out)});
                print("\n", .{});
            },

            else => {
                print("{}\n", .{err});
            },
        }
    };
}

pub fn fileTypeMap(mode: vim_like.Mode, file_type: []const u8, key: Key, function: core.input.MappingSystem.FunctionType) void {
    vim_like.putMapping(mode, file_type, key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    const f = input.functionKey;
    map(.normal, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.insert, &.{f(.none, .escape)}, vim_like.setNormalMode);
    map(.visual, &.{f(.none, .escape)}, vim_like.setNormalMode);

    setDefaultMappnigsNormalMode();
    setDefaultMappnigsInsertMode();
    setDefaultMappnigsVisualMode();
}

fn setDefaultMappnigsNormalMode() void {
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
