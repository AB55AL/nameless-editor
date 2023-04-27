const std = @import("std");

const imgui = @import("imgui");

const core = @import("core");

const editor_ui = @import("editor_ui.zig");
const Buffer = core.Buffer;
const globals = core.globals;
const editor = globals.editor;

const getBuffer = core.getBuffer;

pub fn inspectEditor(arena: std.mem.Allocator) void {
    defer imgui.end();
    if (!imgui.begin("editor inspector", .{})) return;

    _ = imgui.beginTabBar("Tabs", .{});
    defer imgui.endTabBar();

    if (imgui.beginTabItem("buffer inspector", .{})) {
        defer imgui.endTabItem();
        inspectBuffers(arena);
    }

    if (imgui.beginTabItem("Commands", .{})) {
        defer imgui.endTabItem();

        imgui.beginTable("Commands table", .{ .column = 2, .flags = .{ .row_bg = true } });
        defer imgui.endTable();

        imgui.tableSetupColumn("Command", .{ .flags = .{ .width_stretch = true } });
        imgui.tableSetupColumn("Description", .{ .flags = .{ .width_stretch = true } });
        imgui.tableHeadersRow();

        var iter = globals.editor.cli.functions.iterator();
        while (iter.next()) |kv| {
            imgui.tableNextRow(.{});
            const com = kv.key_ptr.*;
            const desc = kv.value_ptr.*.description;
            _ = imgui.tableSetColumnIndex(0);
            var clicked = imgui.selectable(editor_ui.tmpStringZ("{s}", .{com}), .{});
            _ = imgui.tableSetColumnIndex(1);
            clicked = clicked or imgui.selectable(editor_ui.tmpStringZ("{s}", .{desc}), .{});

            open_cli: {
                if (clicked) {
                    core.command_line.open();
                    var cli = &(core.focusedBW().?.data);
                    var cli_buffer = core.cliBuffer();
                    cli_buffer.clear() catch break :open_cli;
                    cli_buffer.insertAt(0, " ") catch break :open_cli;
                    cli_buffer.insertAt(0, com) catch break :open_cli;
                    cli.setCursorCol(Buffer.Point.last_col);
                }
            }
        }
    }

    if (imgui.beginTabItem("Registers", .{})) {
        defer imgui.endTabItem();

        imgui.beginTable("Registers", .{ .column = 2, .flags = .{ .row_bg = true } });
        defer imgui.endTable();

        imgui.tableSetupColumn("Register", .{ .flags = .{ .width_stretch = true } });
        imgui.tableSetupColumn("Value", .{ .flags = .{ .width_stretch = true } });
        imgui.tableHeadersRow();

        var iter = editor.registers.data.iterator();
        while (iter.next()) |kv| {
            imgui.tableNextRow(.{});
            const reg = kv.key_ptr.*;
            const val = kv.value_ptr.*;
            _ = imgui.tableSetColumnIndex(0);
            imgui.textUnformatted(reg);
            _ = imgui.tableSetColumnIndex(1);
            imgui.textUnformatted(val);
        }
    }
}

pub fn inspectBuffers(arena: std.mem.Allocator) void {
    const static = struct {
        var selected: ?core.BufferHandle = null;
        var buf = [_:0]u8{0} ** 1000;
        var big_buf: [10_000]u8 = undefined;
    };

    if (editor.buffers.count() == 0) return;

    { // get the buffers
        var width: f32 = 250;
        _ = imgui.beginChild("Buffers", .{ .w = width, .flags = .{
            .horizontal_scrollbar = true,
        } });
        defer imgui.endChild();

        var iter = editor.buffers.iterator();
        while (iter.next()) |kv| {
            const b = kv.value_ptr;
            const m = b.metadata;
            const string = blk: {
                // shorten /home/user to ~/
                if (m.file_path.len > 0) {
                    const home = std.os.getenv("HOME");
                    if (home) |h|
                        break :blk editor_ui.tmpStringZ("{s}{s}", .{ "~/", m.file_path[h.len + 1 ..] })
                    else
                        break :blk editor_ui.tmpStringZ("{s}", .{m.file_path});
                } else if (b == core.cliBuffer())
                    break :blk editor_ui.tmpStringZ("CLI Buffer", .{})
                else
                    break :blk editor_ui.tmpStringZ("zero length file path", .{});
            };

            if (imgui.selectable(string, .{ .flags = .{} })) static.selected = kv.key_ptr.*;
            if (imgui.isItemHovered(.{}) and imgui.beginTooltip()) {
                defer imgui.endTooltip();
                imgui.text("{s}", .{@as([*:0]u8, string)});
            }
        }
    }

    imgui.sameLine(.{});

    const selected_bhandle = static.selected orelse return;
    var buffer = getBuffer(selected_bhandle).?;

    // All code below displays information about a single buffer

    imgui.beginGroup();
    defer imgui.endGroup();

    _ = imgui.beginChild("Buffer view", .{ .flags = .{
        .horizontal_scrollbar = true,
    } });
    defer imgui.endChild();

    _ = imgui.beginTabBar("buffer fields", .{});
    defer imgui.endTabBar();

    { // metadata
        if (imgui.beginTabItem("metadata", .{})) {
            defer imgui.endTabItem();
            imgui.text("Handle: {}", .{selected_bhandle.handle});
            imgui.text("File path: {s}", .{buffer.metadata.file_path});
            imgui.text("File type: {s}", .{buffer.metadata.file_type});
            imgui.text("Dirty: {}", .{buffer.metadata.dirty});
            imgui.text("Dirty history: {}", .{buffer.metadata.history_dirty});
            imgui.text("Last mod time: {}", .{buffer.metadata.file_last_mod_time});
        }
    }

    selection: {
        if (imgui.beginTabItem("selection", .{})) {
            defer imgui.endTabItem();
            if (!buffer.selection.selected()) {
                imgui.textUnformatted("No selection");
                break :selection;
            }

            var buffer_window = blk: {
                var array = globals.editor.visiable_buffers_tree.treeToArray(arena) catch break :selection;
                for (array) |bw| {
                    if (bw.data.bhandle.handle == selected_bhandle.handle) break :blk &bw.data;
                }
                break :selection;
            };

            const selection = buffer.selection.get(buffer_window.cursor());
            const start = selection.start;
            const end = selection.end;
            imgui.text("start.row {} start.col {}", .{ start.row, start.col });
            imgui.text("end.row {} end.col {}", .{ end.row, end.col });

            if (imgui.button("regular", .{})) buffer.selection.kind = .regular;
            imgui.sameLine(.{});
            if (imgui.button("line", .{})) buffer.selection.kind = .line;
            imgui.sameLine(.{});
            if (imgui.button("block", .{})) buffer.selection.kind = .block;

            _ = imgui.beginChild("selection content", .{ .border = true, .flags = .{
                .horizontal_scrollbar = true,
            } });
            defer imgui.endChild();

            // TODO: print differently when selection.kind.block is set
            var iter = Buffer.LineIterator.initPoint(buffer, selection);
            while (iter.next()) |string| {
                imgui.textUnformatted(string);
                if (string[string.len - 1] != '\n') imgui.sameLine(.{ .spacing = 0 });
            }
        }
    }

    search: {
        if (imgui.beginTabItem("search", .{})) {
            defer imgui.endTabItem();

            _ = imgui.inputText("Search", .{ .buf = &static.buf });
            const len = std.mem.len(@as([*:0]u8, &static.buf));

            var indices = buffer.search(arena, static.buf[0..len], 1, buffer.lineCount()) catch break :search;

            if (indices != null) {
                for (indices.?) |index| {
                    const rc = buffer.getPoint(index);
                    var line = buffer.getLineBuf(&static.big_buf, rc.row);
                    imgui.text("Point {} {} I {}:{s}\n", .{ rc.row, rc.col, index, line });
                }
            }
        }

        break :search;
    }
}
