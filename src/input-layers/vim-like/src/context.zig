const std = @import("std");
const fs = std.fs;
const print = std.debug.print;

const input_layer_main = @import("main.zig");
const vim_like = @import("vim-like.zig");
const core = @import("core");

const editor = core.editor;
const input = core.input;
const Key = input.Key;

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
