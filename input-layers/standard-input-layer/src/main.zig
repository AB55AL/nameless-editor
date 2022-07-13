const std = @import("std");
const print = std.debug.print;

const core = @import("core");
const input = core.input;
const Cursor = core.Cursor;

extern var buffer: *core.Buffer;

var gpa: std.heap.GeneralPurposeAllocator(.{}) = undefined;
var allocator: std.mem.Allocator = undefined;
var mappings: std.StringHashMap(fn () void) = undefined;

pub fn inputLayerInit() void {
    gpa = std.heap.GeneralPurposeAllocator(.{}){};
    allocator = gpa.allocator();
    mappings = std.StringHashMap(fn () void).init(allocator);
    setDefaultMappnigs();
}

pub fn inputLayerDeinit() void {
    mappings.deinit();
    _ = gpa.deinit();
}

pub fn keyInput(key: []const u8) void {
    if (mappings.get(key)) |f|
        f();
}

pub fn characterInput(utf8_seq: []const u8) void {
    buffer.insert(
        buffer.cursor.row,
        buffer.cursor.col,
        utf8_seq,
    ) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };
    Cursor.moveRelative(buffer, 0, 1);
}

pub fn map(key: []const u8, function: fn () void) void {
    mappings.put(key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    map("C_z", undo);
    map("C_y", redo);

    map("<BACKSPACE>", deleteBackward);
    map("<DELETE>", deleteForward);

    map("<RIGHT>", moveRight);
    map("<LEFT>", moveLeft);
    map("<UP>", moveUp);
    map("<DOWN>", moveDown);

    map("<ENTER>", insertNewLineAtCursor);
}

fn undo() void {
    core.history.undo(buffer) catch |err| {
        print("input_layer.undo()\n\t{}\n", .{err});
    };
}
fn redo() void {
    core.history.redo(buffer) catch |err| {
        print("input_layer.redo()\n\t{}\n", .{err});
    };
}

fn deleteBackward() void {
    if (buffer.cursor.col > 1) {
        Cursor.moveRelative(buffer, 0, -1);
        buffer.delete(buffer.cursor.row, buffer.cursor.col, buffer.cursor.col + 1) catch |err| {
            print("input_layer.deleteBackward()\n\t{}\n", .{err});
        };
    }
}

fn deleteForward() void {
    buffer.delete(buffer.cursor.row, buffer.cursor.col, buffer.cursor.col + 1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
fn updateHistory() void {
    core.history.updateHistory(buffer) catch |err| {
        print("input_layer.updateHistory()\n\t{}\n", .{err});
    };
}

fn moveRight() void {
    Cursor.moveRelative(buffer, 0, 1);
}
fn moveLeft() void {
    Cursor.moveRelative(buffer, 0, -1);
}
fn moveUp() void {
    Cursor.moveRelative(buffer, -1, 0);
}
fn moveDown() void {
    Cursor.moveRelative(buffer, 1, 0);
}

fn insertNewLineAtCursor() void {
    buffer.insert(buffer.cursor.row, buffer.cursor.col, "\n") catch |err| {
        print("input_layer.insertNewLineAtCursor()\n\t{}\n", .{err});
    };
    Cursor.moveRelative(buffer, 1, 0);
    Cursor.moveToStartOfLine(buffer);
}
