const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const builtin = @import("builtin");

const ts = @cImport(@cInclude("tree_sitter/api.h"));
const ts_languages = @import("tree_sitter_languages.zig");

const Registers = @import("editor/registers.zig");
const buffer_window = @import("editor/buffer_window.zig");
const BufferWindow = buffer_window.BufferWindow;
const editor_api = @import("editor/editor.zig");
const Buffer = @import("editor/buffer.zig");
const notify = @import("ui/notify.zig");
const utils = @import("utils.zig");
const BufferWindowTree = buffer_window.BufferWindowTree;
const BufferWindowNode = buffer_window.BufferWindowNode;
const command_line = @import("editor/command_line.zig");
const EditorHooks = @import("editor/hooks.zig").EditorHooks;
const ui_api = @import("ui/ui.zig");
const TreeSitterData = @import("editor/tree_sitter.zig").TreeSitterData;

const StringSet = std.StringHashMap(void);
const UserUISet = std.AutoHashMapUnmanaged(ui_api.UserUI, void);
const BufferDisplayerMap = std.StringHashMapUnmanaged(ui_api.BufferDisplayer);
const BufferMap = std.AutoHashMapUnmanaged(editor_api.BufferHandle, Buffer);
const Key = @import("editor/input.zig").Key;

pub const editor = struct {
    pub var registers: Registers = undefined;

    /// A hashmap of all the buffers in the editor
    pub var buffers = BufferMap{};

    pub var hooks: EditorHooks = undefined;

    pub var visiable_buffers_tree = BufferWindowTree{};
    pub var focused_buffer_window: ?*BufferWindowNode = null;
    pub var previous_focused_buffer_wins = std.BoundedArray(*BufferWindowNode, 50).init(0) catch unreachable;

    pub var cli: command_line.CommandLine = undefined;

    pub var tree_sitter: TreeSitterData = undefined;
    pub var ts_langs: std.StringHashMap(*ts.TSLanguage) = undefined;

    /// A set of heap allocated string who's lifetime matches the editor's lifetime.
    pub var string_storage: StringSet = undefined;
};

pub const ui = struct {
    pub var buffer_displayers = BufferDisplayerMap{};

    pub var notifications: notify.Notifications = undefined;

    pub var user_ui = UserUISet{};

    // Only for the focused buffer
    pub var focused_cursor_rect: ?buffer_window.Rect = null;

    pub var show_buffers = true;
    pub var imgui_demo = builtin.mode == .Debug;
    pub var inspect_editor = builtin.mode == .Debug;
    pub var focus_buffers = true;
};

pub const internal = struct {
    /// Global allocator
    pub var allocator: std.mem.Allocator = undefined;
    pub var extra_frames: u32 = 2;

    pub var key_queue = editor_api.KeyQueue.init(0) catch unreachable;
    pub var char_queue = editor_api.CharQueue.init(0) catch unreachable;
};

pub fn initGlobals(allocator: std.mem.Allocator) !void {
    editor.string_storage = StringSet.init(allocator);
    ui.notifications = notify.Notifications.init();
    internal.allocator = allocator;
    editor.registers = Registers.init(allocator);
    try command_line.init();
    editor.hooks = EditorHooks.init(allocator);

    editor.tree_sitter = TreeSitterData.init(allocator);
    editor.ts_langs = try ts_languages.init(allocator);
}

pub fn deinitGlobals() void {
    // zig fmt: off
    { var iter = editor.buffers.valueIterator(); while (iter.next()) |buffer| buffer.deinitNoDestroy(); }
    editor.buffers.deinit(internal.allocator);

    ui.buffer_displayers.deinit(internal.allocator);

    editor.visiable_buffers_tree.deinitTree(internal.allocator, null);
    ui.user_ui.deinit(internal.allocator);

    editor.hooks.deinit();

    editor.registers.deinit();
    command_line.deinit();
    ui.notifications.deinit();

    editor.tree_sitter.deinit();
    editor.ts_langs.deinit();


    { var iter = editor.string_storage.keyIterator(); while (iter.next()) |string| editor.string_storage.allocator.free(string.*); }
    editor.string_storage.deinit();

    // zig fmt: on
}
