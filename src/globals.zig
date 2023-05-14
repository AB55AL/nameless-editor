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
const BufferNodeCycle = std.BoundedArray(*BufferWindowNode, 50);

const default_commands = @import("editor/default_commands.zig");

const StringSet = std.StringHashMap(void);
const UserUISet = std.AutoHashMapUnmanaged(ui_api.UserUI, void);
const BufferDisplayerMap = std.StringHashMapUnmanaged(ui_api.BufferDisplayer);
const BufferMap = std.AutoHashMapUnmanaged(editor_api.BufferHandle, Buffer);
const Key = @import("editor/input.zig").Key;

pub var globals: ?*Globals = null;

pub const Globals = struct {
    ////////////////////////////////////////////////////////////////////////////
    // editor

    registers: Registers,
    /// A hashmap of all the buffers in the editor
    buffers: BufferMap = .{},
    hooks: EditorHooks,
    visiable_buffers_tree: BufferWindowTree = .{},
    cli: command_line.CommandLine,
    tree_sitter: TreeSitterData,
    ts_langs: std.StringHashMap(*ts.TSLanguage),
    /// A set of heap allocated string who's lifetime matches the editor's lifetime.
    string_storage: StringSet,

    previous_focused_buffer_wins: BufferNodeCycle,
    focused_buffer_window: ?*BufferWindowNode = null,

    ////////////////////////////////////////////////////////////////////////////
    // ui

    buffer_displayers: BufferDisplayerMap = .{},
    notifications: notify.Notifications,
    user_ui: UserUISet = .{},
    /// Only for the focused buffer
    focused_cursor_rect: ?buffer_window.Rect = null,
    show_buffers: bool = true,
    imgui_demo: bool = builtin.mode == .Debug,
    inspect_editor: bool = builtin.mode == .Debug,
    focus_buffers: bool = true,

    ////////////////////////////////////////////////////////////////////////////
    // internal

    /// Global allocator
    allocator: std.mem.Allocator,
    extra_frames: u32 = 2,

    key_queue: editor_api.KeyQueue,
    char_queue: editor_api.CharQueue,

    pub fn init(allocator: std.mem.Allocator) !Globals {
        // cli init
        const cli_bhandle = editor_api.generateHandle();
        var cli = try command_line.CommandLine.init(allocator, cli_bhandle);
        try default_commands.setDefaultCommands(&cli);

        var gs = Globals{
            .string_storage = StringSet.init(allocator),
            .notifications = notify.Notifications.init(),
            .allocator = allocator,
            .registers = Registers.init(allocator),
            .cli = cli,
            .key_queue = editor_api.KeyQueue.init(0) catch unreachable,
            .char_queue = editor_api.CharQueue.init(0) catch unreachable,
            .previous_focused_buffer_wins = BufferNodeCycle.init(0) catch unreachable,
            .hooks = EditorHooks.init(allocator),
            .tree_sitter = TreeSitterData.init(allocator),
            .ts_langs = try ts_languages.init(allocator),
        };

        // continue cli init
        try gs.buffers.put(allocator, cli_bhandle, try editor_api.createLocalBuffer(allocator, "", cli_bhandle));

        return gs;
    }

    pub fn deinit(g: *Globals) void {
        // zig fmt: off
        { var iter = g.buffers.valueIterator(); while (iter.next()) |buffer| buffer.deinitNoDestroy(); }
        g.buffers.deinit(g.allocator);
        g.buffer_displayers.deinit(g.allocator);
        g.visiable_buffers_tree.deinitTree(g.allocator, null);
        g.user_ui.deinit(g.allocator);
        g.hooks.deinit();
        g.registers.deinit();
        g.cli.deinit();
        g.notifications.deinit();
        g.tree_sitter.deinit();
        g.ts_langs.deinit();
        { var iter = g.string_storage.keyIterator(); while (iter.next()) |string| g.string_storage.allocator.free(string.*); }
        g.string_storage.deinit();

        // zig fmt: on
    }
};
