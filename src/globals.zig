const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

// const core = @import("core");

const buffer_ui = @import("ui/buffer.zig");
const BufferWindow = buffer_ui.BufferWindow;
const buffer_ops = @import("editor/buffer_ops.zig");
const Buffer = @import("editor/buffer.zig");
const notify = @import("ui/notify.zig");
const utils = @import("utils.zig");
const BufferWindowTree = buffer_ui.BufferWindowTree;
const BufferWindowNode = buffer_ui.BufferWindowNode;

pub const editor = struct {
    /// A linked list of all the buffers in the editor
    pub var first_buffer: ?*Buffer = null;
    /// The number of valid buffers in the linked list
    pub var valid_buffers_count: u32 = 0;
    /// The buffer of the command_line
    pub var command_line_buffer: *Buffer = undefined;
    pub var command_line_is_open: bool = false;
};

pub const ui = struct {
    pub var visiable_buffers_tree = BufferWindowTree{};
    pub var focused_buffer_window: ?*BufferWindowNode = null;
    pub var previous_focused_buffer_wins = std.BoundedArray(*BufferWindowNode, 50).init(0) catch unreachable;

    pub var command_line_buffer_window: BufferWindowNode = undefined;

    pub var notifications = std.BoundedArray(notify.Notify, 1024).init(0) catch unreachable;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
};

pub fn initGlobals(allocator: std.mem.Allocator) !void {
    internal.allocator = allocator;

    editor.command_line_buffer = try buffer_ops.createLocalBuffer("");

    ui.command_line_buffer_window = .{ .data = .{
        .buffer = editor.command_line_buffer,
        .first_visiable_row = 1,
    } };
}

pub fn deinitGlobals() void {
    var buffer: ?*Buffer = editor.first_buffer;
    while (buffer) |b| {
        buffer = b.next_buffer;
        b.deinit();
    }

    editor.command_line_buffer.deinitAndDestroy();
    ui.visiable_buffers_tree.deinitTree(internal.allocator);
}
