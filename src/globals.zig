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
    pub var drawer_window_is_open: bool = undefined;
    pub var drawer_buffer: *Buffer = undefined;
    pub var previous_buffer_index: u32 = undefined;
};

pub const ui = struct {
    pub var state: State = undefined;
    pub var visiable_buffers: [4]?buffer_ui.BufferWindow = .{ null, null, null, null };
    var notify_array: [100]notify.Notify = undefined;
    pub var notifications = utils.FixedArray(notify.Notify).init(&notify_array);
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
};

pub fn initGlobals(allocator: std.mem.Allocator, window_width: u32, window_height: u32) !void {
    internal.allocator = allocator;
    editor.command_line_is_open = false;
    editor.drawer_window_is_open = false;
    editor.command_line_buffer = try internal.allocator.create(Buffer);
    editor.command_line_buffer.* = try Buffer.init(internal.allocator, "", "");

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
        var buffer = first_buffer;
        while (buffer.next_buffer) |nb| {
            switch (buffer.state) {
                .valid => buffer.deinitAndDestroy(internal.allocator),
                .invalid => internal.allocator.destroy(buffer),
            }
            buffer = nb;
        } else {
            switch (buffer.state) {
                .valid => buffer.deinitAndDestroy(internal.allocator),
                .invalid => internal.allocator.destroy(buffer),
            }
        }
    }

    ui.state.deinit(internal.allocator);

    editor.command_line_buffer.deinitAndDestroy(internal.allocator);
}
