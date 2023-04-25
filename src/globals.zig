const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

const registers = @import("editor/registers.zig");
const buffer_window = @import("editor/buffer_window.zig");
const BufferWindow = buffer_window.BufferWindow;
const buffer_ops = @import("editor/buffer_ops.zig");
const Buffer = @import("editor/buffer.zig");
const notify = @import("ui/notify.zig");
const utils = @import("utils.zig");
const BufferWindowTree = buffer_window.BufferWindowTree;
const BufferWindowNode = buffer_window.BufferWindowNode;
const command_line = @import("editor/command_line.zig");
const EditorHooks = @import("editor/hooks.zig").EditorHooks;

pub const UserUIFunc = *const fn (gpa: std.mem.Allocator, arena: std.mem.Allocator) void;
const UserUIFuncSet = std.AutoHashMap(UserUIFunc, void);
const BufferMap = std.AutoHashMapUnmanaged(buffer_ops.BufferHandle, Buffer);

const Key = @import("editor/input.zig").Key;

pub const editor = struct {
    pub var command_function_lut: std.StringHashMap(command_line.CommandType) = undefined;
    pub var registers = std.StringHashMapUnmanaged([]const u8){};

    /// A hashmap of all the buffers in the editor
    pub var buffers = BufferMap{};
    pub var command_line_is_open: bool = false;

    pub var hooks: EditorHooks = undefined;

    pub var visiable_buffers_tree = BufferWindowTree{};
    pub var focused_buffer_window: ?*BufferWindowNode = null;
    pub var previous_focused_buffer_wins = std.BoundedArray(*BufferWindowNode, 50).init(0) catch unreachable;
    pub var command_line_buffer_window: BufferWindowNode = undefined;
};

pub const input = struct {
    pub var key_queue = std.BoundedArray(Key, 1024).init(0) catch unreachable;
    pub var char_queue = std.BoundedArray(u21, 1024).init(0) catch unreachable;
};

pub const ui = struct {
    pub var notifications = std.BoundedArray(notify.Notify, 1024).init(0) catch unreachable;

    pub var user_ui: UserUIFuncSet = undefined;

    // Only for the focused buffer
    pub var focused_cursor_rect: ?buffer_window.Rect = null;

    pub var gui_full_size = true;
    pub var imgui_demo = builtin.mode == .Debug;
    pub var inspect_editor = builtin.mode == .Debug;
    pub var focus_buffers = true;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
    pub var extra_frame = true;
};

pub fn initGlobals(allocator: std.mem.Allocator) !void {
    internal.allocator = allocator;

    ui.user_ui = UserUIFuncSet.init(allocator);

    { // command line
        const cli_bhandle = buffer_ops.generateHandle();
        const command_line_buffer = try buffer_ops.createLocalBuffer("");
        try editor.buffers.put(internal.allocator, cli_bhandle, command_line_buffer);

        const bw = try BufferWindow.init(cli_bhandle, 1, .north, 0, @ptrToInt(&editor.command_line_buffer_window));
        editor.command_line_buffer_window = .{ .data = bw };
    }

    editor.hooks = EditorHooks.init(allocator);
}

pub fn deinitGlobals() void {
    var iter = editor.buffers.valueIterator();
    while (iter.next()) |buffer| buffer.deinitNoDestroy();
    editor.buffers.deinit(internal.allocator);

    editor.visiable_buffers_tree.deinitTree(internal.allocator, null);
    ui.user_ui.deinit();

    editor.hooks.deinit();

    registers.deinit();
}
