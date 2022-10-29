const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const fs = std.fs;
const StringArrayHashMap = std.StringArrayHashMap;
const StringHashMap = std.StringHashMap;

const core = @import("core");
const Cursor = core.Cursor;
const layouts = @import("../../../plugins/layouts.zig");

const global = core.global;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
var ft_mappings: InputHandler = undefined;
var log_file: fs.File = undefined;

pub const InputHandler = struct {
    pub const FunctionType = *const fn () void;
    table: StringArrayHashMap(*StringHashMap(FunctionType)),

    pub fn init(alloc: std.mem.Allocator) !InputHandler {
        return .{
            .table = StringArrayHashMap(*StringHashMap(FunctionType)).init(alloc),
        };
    }

    pub fn deinit(ih: *InputHandler) void {
        while (ih.table.popOrNull()) |*element| {
            element.value.deinit();
            ih.table.allocator.destroy(element.value);
        }
        ih.table.deinit();
    }

    pub fn addFileType(ih: *InputHandler, file_type: []const u8) !void {
        var m = try ih.table.allocator.create(StringHashMap(FunctionType));
        m.* = StringHashMap(FunctionType).init(ih.table.allocator);
        try ih.table.put(file_type, m);
    }

    pub fn get(ih: *InputHandler, file_type: []const u8, key: []const u8) ?FunctionType {
        var ft = ih.table.get(file_type);
        if (ft == null) return null;

        var function = ft.?.get(key);
        return function;
    }

    pub fn put(ih: *InputHandler, file_type: []const u8, key: []const u8, function: FunctionType) !void {
        var table = ih.table.get(file_type) orelse blk: {
            try ih.addFileType(file_type);
            break :blk ih.table.get(file_type).?;
        };
        try table.put(key, function);
    }

    pub fn getOrPut(ih: *InputHandler, file_type: []const u8, key: []const u8, function: FunctionType) !FunctionType {
        return ih.get(file_type, key) orelse ih.put(file_type, key, function);
    }
};

pub fn init() !void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
    ft_mappings = try InputHandler.init(allocator);
    try ft_mappings.addFileType(""); // Global and fallback file_type
    setDefaultMappnigs();

    const data_path = std.os.getenv("XDG_DATA_HOME") orelse return;
    const log_path = try std.mem.concat(allocator, u8, &.{ data_path, "/ne" });
    defer allocator.free(log_path);
    var dir = fs.openDirAbsolute(log_path, .{}) catch return;
    defer dir.close();

    log_file = try (dir.openFile("input-log", .{ .mode = .write_only }) catch |err| if (err == fs.Dir.OpenError.FileNotFound)
        dir.createFile("input-log", .{})
    else
        err);

    const end = log_file.getEndPos() catch return;
    _ = log_file.pwrite("\n---------------new editor instance---------------\n", end) catch |err| print("err={}", .{err});
}

pub fn deinit() void {
    ft_mappings.deinit();
    log_file.close();
    _ = gpa.deinit();
}

pub fn keyInput(key: []const u8) void {
    var file_type = core.global.focused_buffer.metadata.file_type;
    var k = ft_mappings.get(file_type, key);
    if (k) |f| {
        f();
        const end = log_file.getEndPos() catch return;
        _ = log_file.pwrite(key, end) catch |err| print("err={}", .{err});
        _ = log_file.pwrite("\n", end + key.len) catch |err| print("err={}", .{err});
    } else if (file_type.len > 0) { // fallback
        if (ft_mappings.get("", key)) |f| {
            f();
            const end = log_file.getEndPos() catch return;
            _ = log_file.pwrite(key, end) catch |err| print("err={}", .{err});
            _ = log_file.pwrite("\n", end + key.len) catch |err| print("err={}", .{err});
        }
    }
}

pub fn characterInput(utf8_seq: []const u8) void {
    global.focused_buffer.insertBeforeCursor(utf8_seq) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };

    const end = log_file.getEndPos() catch return;
    const insert = "insert:";
    _ = log_file.pwrite(insert, end) catch |err| print("err={}", .{err});
    _ = log_file.pwrite(utf8_seq, end + insert.len) catch |err| print("err={}", .{err});
    _ = log_file.pwrite("\n", end + insert.len + utf8_seq.len) catch |err| print("err={}", .{err});
}

pub fn map(key: []const u8, function: InputHandler.FunctionType) void {
    ft_mappings.put("", key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

pub fn fileTypeMap(file_type: []const u8, key: []const u8, function: InputHandler.FunctionType) void {
    ft_mappings.put(file_type, key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    map("<F3>", core.closeDrawerWindow);
    map("<BACKSPACE>", deleteBackward);
    map("<DELETE>", deleteForward);

    map("<RIGHT>", moveRight);
    map("<LEFT>", moveLeft);
    map("<UP>", moveUp);
    map("<DOWN>", moveDown);

    map("<ENTER>", enterKey);
    map("<F1>", toggleCommandLine);
}

fn deleteBackward() void {
    global.focused_buffer.deleteBeforeCursor(1) catch |err| {
        print("input_layer.deleteBackward()\n\t{}\n", .{err});
    };
}

fn deleteForward() void {
    global.focused_buffer.deleteAfterCursor(1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
fn moveRight() void {
    global.focused_buffer.moveRelativeColumn(1);
}
fn moveLeft() void {
    global.focused_buffer.moveRelativeColumn(-1);
}
fn moveUp() void {
    global.focused_buffer.moveRelativeRow(-1);
}
fn moveDown() void {
    global.focused_buffer.moveRelativeRow(1);
}

fn toggleCommandLine() void {
    if (global.command_line_is_open)
        core.command_line.close()
    else
        core.command_line.open();
}

fn enterKey() void {
    if (global.command_line_is_open)
        core.command_line.run() catch |err| {
            print("Couldn't run command. err={}\n", .{err});
        }
    else
        insertNewLineAtCursor();
}

fn insertNewLineAtCursor() void {
    global.focused_buffer.insertBeforeCursor("\n") catch |err| {
        print("input_layer.insertNewLineAtCursor()\n\t{}\n", .{err});
    };
}
