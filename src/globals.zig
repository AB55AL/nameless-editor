const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;

const State = @import("ui/ui_lib.zig").State;
const buffer_ops = @import("editor/buffer_ops.zig");
const Buffer = @import("editor/buffer.zig");
const BufferNode = buffer_ops.BufferNode;
const shape2d = @import("ui/shape2d.zig");
const ui_lib = @import("ui/ui_lib.zig");
const notify = @import("ui/notify.zig");
const utils = @import("utils.zig");
const buffer_ui = @import("ui/buffer.zig");
const DrawList = @import("ui/draw_command.zig").DrawList;

pub const editor = struct {
    /// A Pointer to the currently focused buffer
    pub var focused_buffer: ?*Buffer = null;
    /// A linked list of all the buffers in the editor
    pub var first_buffer: ?*Buffer = undefined;
    /// The number of valid buffers in the linked list
    pub var valid_buffers_count: u32 = 0;
    /// The buffer of the command_line
    pub var command_line_buffer: *Buffer = undefined;
    pub var command_line_is_open: bool = undefined;
    pub var previous_buffer_index: u32 = undefined;
};

pub const ui = struct {
    pub var state: State = undefined;
    // TODO: Find a better way of presenting visiable_buffers using panels
    pub var visiable_buffers: [2]?buffer_ui.BufferWindow = .{ null, null };
    pub var focused_buffer_window: ?*buffer_ui.BufferWindow = null;
    pub var command_line_buffer_window: buffer_ui.BufferWindow = undefined;
    var notify_array: [100]notify.Notify = undefined;
    pub var notifications = utils.FixedArray(notify.Notify).init(&notify_array);

    pub var visiable_buffers_tree: ?*buffer_ui.BufferWindow = null;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
};

pub fn initGlobals(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !void {
    internal.allocator = allocator;
    editor.command_line_is_open = false;
    editor.command_line_buffer = try internal.allocator.create(Buffer);
    editor.command_line_buffer.* = try Buffer.init(internal.allocator, "", "");

    ui.command_line_buffer_window = buffer_ui.BufferWindow{
        .buffer = editor.command_line_buffer,
        .first_visiable_row = 1,
    };

    ui.state = State{
        // .font = try shape2d.Font.init(allocator, "assets/Fira Code Light Nerd Font Complete Mono.otf", 24),
        .font = try shape2d.Font.init(allocator, "assets/Amiri-Regular.ttf", 24),
        .window_width = window_width,
        .window_height = window_height,
        .draw_list = DrawList.init(allocator),
    };
}

pub fn deinitGlobals() void {
    if (editor.first_buffer) |first_buffer| {
        var buffer: ?*Buffer = first_buffer;
        while (buffer) |b| {
            buffer = b.next_buffer;
            b.deinit();
        }
    }

    ui.state.deinit(internal.allocator);

    editor.command_line_buffer.deinitAndDestroy(internal.allocator);
}
