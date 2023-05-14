const std = @import("std");

const imgui = @import("imgui");

const core = @import("core");

const math = @import("math.zig");
const utils = core.utils;

const ts = @cImport(@cInclude("tree_sitter/api.h"));

const editor_ui = @import("editor_ui.zig");
const Buffer = core.Buffer;
const BufferWindow = core.BufferWindow;

var gs = &core.globals.globals;

const tmpStringZ = editor_ui.tmpStringZ;

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

        var iter = core.gs().cli.functions.iterator();
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
                    core.openCLI();
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

        var iter = core.gs().registers.data.iterator();
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

    if (imgui.beginTabItem("Buffer windows", .{})) {
        defer imgui.endTabItem();
        inspectBufferWindows(arena);
    }
}

pub fn inspectBufferWindows(arena: std.mem.Allocator) void {
    const static = struct {
        pub var show_window_border: bool = true;
        pub var show_child_window_border: bool = false;
    };
    var windows = core.gs().visiable_buffers_tree.treeToArray(arena) catch return;

    const child_height = imgui.getTextLineHeightWithSpacing() * 8;

    var dl = imgui.getForegroundDrawList();

    _ = imgui.checkbox("show window border", .{ .v = &static.show_window_border });
    imgui.sameLine(.{});
    _ = imgui.checkbox("show child window border", .{ .v = &static.show_child_window_border });

    for (windows, 0..) |win, i| {
        _ = imgui.beginChild(tmpStringZ("Buffer window child {}", .{i}), .{ .h = child_height });
        defer imgui.endChild();

        var bw = &(win.data);
        var buffer = core.getBuffer(bw.bhandle) orelse continue;
        imgui.text("handle: {} File Path: {s}", .{ bw.bhandle.handle, buffer.metadata.file_path });
        if (win.parent == null)
            imgui.textUnformatted("Root buffer window");

        // zig fmt: off
        imgui.text("Dir:", .{}); imgui.sameLine(.{});
        const north = imgui.radioButton(tmpStringZ("North##{}",.{i}), .{ .active = bw.dir == .north }); imgui.sameLine(.{});
        const east = imgui.radioButton(tmpStringZ("East##{}",.{i}), .{ .active = bw.dir == .east }); imgui.sameLine(.{});
        const south = imgui.radioButton(tmpStringZ("South##{}",.{i}), .{ .active = bw.dir == .south }); imgui.sameLine(.{});
        const west = imgui.radioButton(tmpStringZ("West##{}",.{i}), .{ .active = bw.dir == .west });

        if (north) bw.dir = .north else if (east) bw.dir = .east else if (south) bw.dir = .south else if (west) bw.dir = .west;
        // zig fmt: on

        imgui.text("Lines from {} to {}", .{ bw.first_visiable_row, bw.lastVisibleRow() });
        imgui.text("{}", .{bw.options});
        imgui.text("x: {d:.2} y: {d:.2} w: {d:.2} h: {d:.2}", .{ bw.rect.x, bw.rect.y, bw.rect.w, bw.rect.h });
        imgui.separatorText("");

        if (imgui.isWindowHovered(.{}) and static.show_window_border) {
            dl.addRect(.{
                .pmin = bw.rect.leftTop(),
                .pmax = bw.rect.rightBottom(),
                .col = 0xFF_AAAAAA,
                .thickness = 2,
            });

            if (static.show_child_window_border) {

                // Highlight children
                for (windows[i + 1 ..]) |next_win| {
                    if (next_win.isDescendentOf(win)) {
                        dl.addRect(.{
                            .pmin = math.arrayAdd(next_win.data.rect.leftTop(), .{ 5, 5 }),
                            .pmax = math.arrayAdd(next_win.data.rect.rightBottom(), .{ -5, -5 }),
                            .col = 0xFF_FF0000,
                            .thickness = 2,
                        });
                    }
                }
            }
        }
    }
}

pub fn inspectBuffers(arena: std.mem.Allocator) void {
    const static = struct {
        var selected: ?core.BufferHandle = null;
        var buf = [_:0]u8{0} ** 1000;
        var big_buf: [10_000]u8 = undefined;
    };

    if (core.gs().buffers.count() == 0) return;

    { // get the buffers
        var width: f32 = 250;
        _ = imgui.beginChild("Buffers", .{ .w = width, .flags = .{
            .horizontal_scrollbar = true,
        } });
        defer imgui.endChild();

        var iter = core.gs().buffers.iterator();
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

    if (static.selected == null and core.gs().buffers.size > 1) {
        var iter = core.gs().buffers.iterator();
        var cli_buffer = core.cliBuffer();
        while (iter.next()) |kv| {
            if (kv.value_ptr != cli_buffer) {
                static.selected = kv.key_ptr.*;
                break;
            }
        }
    } else if (static.selected == null) {
        static.selected = core.BufferHandle{ .handle = 0 }; // cli bhandle
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

    {
        if (imgui.beginTabItem("Tree Sitter", .{})) {
            defer imgui.endTabItem();
            treeSitter(arena, buffer, selected_bhandle);
        }
    }

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
                var array = core.gs().visiable_buffers_tree.treeToArray(arena) catch break :selection;
                for (array) |bw| {
                    if (bw.data.bhandle.handle == selected_bhandle.handle) break :blk &bw.data;
                }
                break :selection;
            };

            const cursor = buffer_window.cursor() orelse break :selection;
            const selection = buffer.selection.get(cursor);
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

pub fn treeSitter(arena: std.mem.Allocator, buffer: *Buffer, bhandle: core.BufferHandle) void {
    const static = struct {
        var start_row: i32 = 0;
        var start_col: i32 = 0;
        var end_row: i32 = 1;
        var end_col: i32 = 0;

        var buf: [1000:0]u8 = .{0} ** 1000;
        var global_query_name: [1000:0]u8 = .{0} ** 1000;
    };

    _ = imgui.sliderInt("Start row", .{ .v = &static.start_row, .min = 0, .max = @intCast(i32, buffer.lineCount() -| 1) });
    _ = imgui.sliderInt("Start col", .{ .v = &static.start_col, .min = 0, .max = @intCast(i32, buffer.countCodePointsAtRow(@intCast(u32, static.start_col + 1))) });
    _ = imgui.sliderInt("End row", .{ .v = &static.end_row, .min = 0, .max = @intCast(i32, buffer.lineCount()) });
    _ = imgui.sliderInt("End col", .{ .v = &static.end_col, .min = 0, .max = @intCast(i32, buffer.countCodePointsAtRow(@intCast(u32, static.end_row + 1))) });

    _ = imgui.inputText("Query", .{ .buf = &static.buf });
    _ = imgui.inputText("Global Query Name", .{ .buf = &static.global_query_name });

    var ts_zig = core.getTSLang("zig") orelse return;
    const tree = core.tree_sitter.getTree(bhandle) orelse return;

    var root = ts.ts_tree_root_node(tree);
    if (!ts.ts_node_is_null(root)) {
        const start = ts.TSPoint{ .row = @intCast(u32, static.start_row), .column = @intCast(u32, static.start_col) };
        const end = ts.TSPoint{ .row = @intCast(u32, static.end_row + 2), .column = @intCast(u32, static.end_col) };

        const static_buf_len = std.mem.len(@as([*c]u8, &static.buf));
        const static_query_name_len = std.mem.len(@as([*c]u8, &static.global_query_name));
        var global_query_data = core.tree_sitter.getQuery(buffer.metadata.file_type, static.global_query_name[0..static_query_name_len]);
        var query_data: core.TreeSitterData.QueryData = if (global_query_data != null and static_buf_len == 0) global_query_data.? else blk: {
            var error_offset: u32 = 0;
            var error_type: u32 = 0;
            var query = ts.ts_query_new(ts_zig, &static.buf, @truncate(u32, static_buf_len), &error_offset, &error_type);

            break :blk .{
                .query = query,
                .error_offset = error_offset,
                .error_type = error_type,
            };
        };

        imgui.text("{s}", .{ts.ts_node_string(root)});

        if (query_data.error_type == ts.TSQueryErrorNone) {
            var qc = ts.ts_query_cursor_new();
            ts.ts_query_cursor_set_point_range(qc, start, end);

            var query = query_data.query;
            ts.ts_query_cursor_exec(qc, query, root);

            imgui.beginTable("Captures", .{ .column = 4, .flags = .{ .row_bg = true } });
            defer imgui.endTable();

            imgui.tableSetupColumn("Index", .{ .flags = .{ .width_stretch = true } });
            imgui.tableSetupColumn("Name", .{ .flags = .{ .width_stretch = true } });
            imgui.tableSetupColumn("String", .{ .flags = .{ .width_stretch = true } });
            imgui.tableSetupColumn("Point Range", .{ .flags = .{ .width_stretch = true } });
            imgui.tableHeadersRow();

            var match: ts.TSQueryMatch = undefined;
            while (ts.ts_query_cursor_next_match(qc, &match)) {
                imgui.tableNextRow(.{});

                if (match.capture_count > 0) {
                    var captures = match.captures[0..match.capture_count];
                    for (captures) |cap| {
                        var sp = ts.ts_node_start_point(cap.node);
                        var ep = ts.ts_node_end_point(cap.node);
                        var si = ts.ts_node_start_byte(cap.node);
                        var ei = ts.ts_node_end_byte(cap.node);
                        var line = buffer.getLine(arena, buffer.rowOfIndex(si).row) catch return;

                        si -= @intCast(u32, buffer.indexOfFirstByteAtRow(buffer.rowOfIndex(si).row));
                        ei -= @intCast(u32, buffer.indexOfFirstByteAtRow(buffer.rowOfIndex(si).row));

                        si = utils.bound(si, 0, @intCast(u32, line.len));
                        ei = utils.bound(ei, 0, @intCast(u32, line.len));
                        var string = line[si..ei];

                        var len: u32 = 0;
                        const name = ts.ts_query_capture_name_for_id(query, cap.index, &len);

                        _ = imgui.tableSetColumnIndex(0);
                        imgui.text("{}", .{cap.index});
                        _ = imgui.tableSetColumnIndex(1);
                        imgui.text("{s}", .{name[0..len]});
                        _ = imgui.tableSetColumnIndex(2);
                        imgui.text("{s}", .{string});
                        _ = imgui.tableSetColumnIndex(3);
                        imgui.text("index {} -> {}\ns {},{}\ne {},{}", .{ si, ei, sp.row, sp.column, ep.row, ep.column });
                    }
                }
            }
        } else {
            const error_string = switch (query_data.error_type) {
                0 => "TSQueryErrorNone",
                1 => "TSQueryErrorSyntax",
                2 => "TSQueryErrorNodeType",
                3 => "TSQueryErrorField",
                4 => "TSQueryErrorCapture",
                5 => "TSQueryErrorStructure",
                6 => "TSQueryErrorLanguage",
                else => unreachable,
            };
            imgui.text("{s}\tOffset: {}", .{ error_string, query_data.error_offset });
        }
    }
}
