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
const Key = input.Key;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
var ft_mappings: Table = undefined;
var log_file: fs.File = undefined;

const Table = struct {
    pub const FunctionType = *const fn () void;
    pub const KeyHashMap = AutoHashMap(Key, FunctionType);
    table: StringArrayHashMap(*KeyHashMap),

    pub fn init(alloc: std.mem.Allocator) !Table {
        return .{
            .table = StringArrayHashMap(*KeyHashMap).init(alloc),
        };
    }

    pub fn deinit(t: *Table) void {
        while (t.table.popOrNull()) |element| {
            element.value.deinit();
            t.table.allocator.destroy(element.value);
        }
        t.table.deinit();
    }

    pub fn addFileType(t: *Table, file_type: []const u8) !void {
        var m = try t.table.allocator.create(KeyHashMap);
        m.* = KeyHashMap.init(t.table.allocator);
        try t.table.put(file_type, m);
    }

    pub fn get(t: *Table, file_type: []const u8, key: Key) ?FunctionType {
        var ft = t.table.get(file_type);
        if (ft == null) return null;

        var function = ft.?.get(key);
        return function;
    }

    pub fn put(t: *Table, file_type: []const u8, key: Key, function: FunctionType) !void {
        var table = t.table.get(file_type) orelse blk: {
            try t.addFileType(file_type);
            break :blk t.table.get(file_type).?;
        };
        try table.put(key, function);
    }

    pub fn getOrPut(t: *Table, file_type: []const u8, key: Key, function: FunctionType) !FunctionType {
        return t.get(file_type, key) orelse t.put(file_type, key, function);
    }
};

pub fn init() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
    ft_mappings = try Table.init(allocator);
    try ft_mappings.addFileType(""); // Global and fallback file_type
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
    ft_mappings.deinit();
    log_file.close();
    _ = gpa.deinit();
}

pub fn keyInput(key: Key) void {
    var file_type = if (core.editor.focused_buffer) |fb| fb.metadata.file_type else "";
    var k = ft_mappings.get(file_type, key);
    if (k) |f| {
        f();
        logKey(key);
    } else if (file_type.len > 0) { // fallback
        if (ft_mappings.get("", key)) |f| {
            f();
            logKey(key);
        }
    }
}

pub fn characterInput(utf8_seq: []const u8) void {
    var fb = core.editor.focused_buffer orelse return;
    fb.insertBeforeCursor(utf8_seq) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };

    var focused_buffer_window = core.ui.focused_buffer_window orelse return;
    focused_buffer_window.setWindowCursorToBuffer();

    const end = log_file.getEndPos() catch return;
    const insert = "insert:";
    _ = log_file.pwrite(insert, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite(utf8_seq, end + insert.len) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + insert.len + utf8_seq.len) catch |err| print("err={}", .{err});
}

pub fn map(key: Key, function: Table.FunctionType) void {
    ft_mappings.put("", key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

pub fn fileTypeMap(file_type: []const u8, key: Key, function: Table.FunctionType) void {
    ft_mappings.put(file_type, key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    const f = input.functionKey;
    const a = input.asciiKey;

    map(a(.control, .v), paste);

    map(a(.control, .d), scrollDown);
    map(a(.control, .u), scrollUp);

    map(f(.none, .backspace), deleteBackward);
    map(f(.none, .delete), deleteForward);

    map(f(.none, .right), moveRight);
    map(f(.none, .left), moveLeft);
    map(f(.none, .up), moveUp);
    map(f(.none, .down), moveDown);

    map(f(.none, .enter), enterKey);
    map(f(.none, .f1), toggleCommandLine);
    map(f(.none, .f2), cycleWindows);
}

fn logKey(key: Key) void {
    const end = log_file.getEndPos() catch return;
    var out: [20]u8 = undefined;
    var key_str = key.toString(&out);

    _ = log_file.pwrite(key_str, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + key_str.len) catch |err| print("err={}", .{err});
}

////////////////////////////////////////////////////////////////////////////////
// Function wrappers
////////////////////////////////////////////////////////////////////////////////

fn paste() void {
    var fb = core.editor.focused_buffer orelse return;

    var clipboard = glfw.getClipboardString() catch {
        core.notify("Clipboard", "Empty", 2000);
        return;
    };
    fb.insertBeforeCursor(clipboard) catch |err| {
        print("input_layer.paste()\n\t{}\n", .{err});
    };
}

fn scrollDown() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.scrollDown(1);
}

fn scrollUp() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.scrollUp(1);
}

fn cycleWindows() void {
    core.nextBufferWindow();
}

fn deleteBackward() void {
    var fb = core.editor.focused_buffer orelse return;
    fb.deleteBeforeCursor(1) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };

    var focused_buffer_window = core.ui.focused_buffer_window orelse return;
    focused_buffer_window.setWindowCursorToBuffer();
}

fn deleteForward() void {
    var fb = core.editor.focused_buffer orelse return;
    fb.deleteAfterCursor(1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
fn moveRight() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeColumn(1, false);
}
fn moveLeft() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeColumn(-1, false);
}
fn moveUp() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeRow(-1);
}
fn moveDown() void {
    var fb = core.ui.focused_buffer_window orelse return;
    fb.moveCursorRelativeRow(1);
}

fn toggleCommandLine() void {
    if (editor.command_line_is_open)
        core.command_line.close()
    else
        core.command_line.open();
}

fn enterKey() void {
    if (editor.command_line_is_open)
        core.command_line.run() catch |err| {
            print("Couldn't run command. err={}\n", .{err});
        }
    else
        insertNewLineAtCursor();
}

fn insertNewLineAtCursor() void {
    characterInput("\n");
}
