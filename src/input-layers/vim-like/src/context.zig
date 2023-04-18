const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

const input_layer_main = @import("main.zig");
const vim_like = @import("vim-like.zig");
const core = @import("core");

pub fn cursorRect(left: f32, top: f32, right: f32, bottom: f32) core.BufferWindow.CursorRect {
    var rect: core.BufferWindow.CursorRect = .{
        .top = top,
        .left = left,
        .bottom = bottom,
        .right = right,
        .col = 0xFFFFFF_FF,
    };

    switch (vim_like.state.mode) {
        .insert => {
            rect.right = rect.left;
        },
        else => {},
    }

    return rect;
}

pub fn init() !void {
    input_layer_main.gpa = std.heap.GeneralPurposeAllocator(.{}){};
    input_layer_main.allocator = input_layer_main.gpa.allocator();
    input_layer_main.arena = std.heap.ArenaAllocator.init(input_layer_main.allocator);
    input_layer_main.arena_allocator = input_layer_main.arena.allocator();

    for (&vim_like.state.mappings) |*m| {
        m.* = core.input.MappingSystem.init(input_layer_main.arena_allocator);
        _ = try m.getOrCreateFileType(""); // Global and fallback file_type
    }
    input_layer_main.setDefaultMappnigs();
    {
        const data_path = std.os.getenv("XDG_DATA_HOME") orelse return;
        const log_path = std.mem.concat(input_layer_main.allocator, u8, &.{ data_path, "/ne" }) catch return;
        defer input_layer_main.allocator.free(log_path);
        var dir = fs.openDirAbsolute(log_path, .{}) catch return;
        defer dir.close();

        input_layer_main.log_file = (dir.openFile("input-log", .{ .mode = .write_only }) catch |err| if (err == fs.Dir.OpenError.FileNotFound)
            dir.createFile("input-log", .{})
        else
            err) catch return;

        const end = input_layer_main.log_file.getEndPos() catch return;
        _ = input_layer_main.log_file.pwrite("\n---------------new editor instance---------------\n", end) catch |err| print("err={}", .{err});
    }
}

pub fn deinit() void {
    input_layer_main.arena.deinit(); // deinit the mappings

    input_layer_main.log_file.close();
    _ = input_layer_main.gpa.deinit();
}

pub fn handleInput() void {
    while (core.globals.input.char_queue.popOrNull()) |cp| {
        var seq: [4]u8 = undefined;
        var bytes = std.unicode.utf8Encode(cp, &seq) catch unreachable;
        input_layer_main.characterInput(seq[0..bytes]);
    }

    while (core.globals.input.key_queue.popOrNull()) |key| {
        input_layer_main.keyInput(key);
    }
}
