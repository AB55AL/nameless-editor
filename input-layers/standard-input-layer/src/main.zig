const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const core = @import("core");
const Cursor = core.Cursor;
const history = core.history;

extern var focused_buffer: *core.Buffer;
extern var global_buffers: ArrayList(core.Buffer);

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
    focused_buffer.insert(
        focused_buffer.cursor.row,
        focused_buffer.cursor.col,
        utf8_seq,
    ) catch |err| {
        print("input_layer.characterInputCallback()\n\t{}\n", .{err});
    };
    Cursor.moveRelative(focused_buffer, 0, 1);
}

pub fn map(key: []const u8, function: fn () void) void {
    mappings.put(key, function) catch |err| {
        print("input_layer.map()\n\t{}\n", .{err});
    };
}

fn setDefaultMappnigs() void {
    map("C_z", undo);
    map("C_y", redo);
    map("<F1>", commitHistoryChanges);
    map("<F2>", insertAlot);
    map("<F3>", cycleThroughBuffers);

    map("<BACKSPACE>", deleteBackward);
    map("<DELETE>", deleteForward);

    map("<RIGHT>", moveRight);
    map("<LEFT>", moveLeft);
    map("<UP>", moveUp);
    map("<DOWN>", moveDown);

    map("<ENTER>", insertNewLineAtCursor);
}

fn cycleThroughBuffers() void {
    const static = struct {
        var i: usize = 0;
    };
    static.i += 1;
    if (static.i >= global_buffers.items.len) static.i = 0;
    focused_buffer = &global_buffers.items[static.i];
}

fn undo() void {
    core.history.undo(focused_buffer) catch |err| {
        print("input_layer.undo()\n\t{}\n", .{err});
    };
}
fn redo() void {
    core.history.redo(focused_buffer) catch |err| {
        print("input_layer.redo()\n\t{}\n", .{err});
    };
}

fn deleteBackward() void {
    if (focused_buffer.cursor.col > 1) {
        Cursor.moveRelative(focused_buffer, 0, -1);
        focused_buffer.delete(focused_buffer.cursor.row, focused_buffer.cursor.col, focused_buffer.cursor.col + 1) catch |err| {
            print("input_layer.deleteBackward()\n\t{}\n", .{err});
        };
    }
}

fn deleteForward() void {
    focused_buffer.delete(focused_buffer.cursor.row, focused_buffer.cursor.col, focused_buffer.cursor.col + 1) catch |err| {
        print("input_layer.deleteForward()\n\t{}\n", .{err});
    };
}
fn updateHistory() void {
    core.history.updateHistory(focused_buffer) catch |err| {
        print("input_layer.updateHistory()\n\t{}\n", .{err});
    };
}

fn moveRight() void {
    Cursor.moveRelative(focused_buffer, 0, 1);
}
fn moveLeft() void {
    Cursor.moveRelative(focused_buffer, 0, -1);
}
fn moveUp() void {
    Cursor.moveRelative(focused_buffer, -1, 0);
}
fn moveDown() void {
    Cursor.moveRelative(focused_buffer, 1, 0);
}

fn insertNewLineAtCursor() void {
    focused_buffer.insert(focused_buffer.cursor.row, focused_buffer.cursor.col, "\n") catch |err| {
        print("input_layer.insertNewLineAtCursor()\n\t{}\n", .{err});
    };
    Cursor.moveRelative(focused_buffer, 1, 0);
    Cursor.moveToStartOfLine(focused_buffer);
}

fn commitHistoryChanges() void {
    history.commitHistoryChanges(focused_buffer) catch unreachable;
}

fn insertAlot() void {
    // focused_buffer.deleteRows(1, 3) catch unreachable;
    focused_buffer.insert(1, 1, "شششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششششش") catch unreachable;
}
