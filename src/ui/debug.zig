const std = @import("std");

const imgui = @import("imgui");

const core = @import("core");

const ui = @import("ui.zig");
const Buffer = core.Buffer;
const globals = core.globals;
const editor = globals.editor;

pub fn inspectBuffers(arena: std.mem.Allocator) void {
    const static = struct {
        var selected: i32 = 0;
    };

    defer imgui.end();
    if (!imgui.begin("buffers inspector", .{})) return;

    if (editor.buffers.first != null) {
        {
            var width: f32 = 250;
            _ = imgui.beginChild("Buffers", .{ .w = width, .flags = .{
                .horizontal_scrollbar = true,
            } });
            defer imgui.endChild();

            var buffer_node = editor.buffers.first;
            while (buffer_node) |bf| {
                defer buffer_node = bf.next;

                const b = &bf.data;
                const m = b.metadata;
                const string = blk: {
                    // shorten /home/user to ~/
                    const home = std.os.getenv("HOME");
                    if (home) |h|
                        break :blk ui.tmpString("{s}{s}", .{ "~/", m.file_path[h.len + 1 ..] })
                    else
                        break :blk ui.tmpString("{s}", .{m.file_path});
                };

                if (imgui.selectable(string, .{ .flags = .{} })) static.selected = @intCast(i32, b.id);
                if (imgui.isItemHovered(.{}) and imgui.beginTooltip()) {
                    defer imgui.endTooltip();
                    imgui.text("{s}", .{@as([*:0]u8, string)});
                }
            }
        }

        imgui.sameLine(.{});

        var buffer = core.getBufferI(@intCast(u32, static.selected)) orelse return;

        imgui.beginGroup();
        defer imgui.endGroup();

        _ = imgui.beginChild("Buffer view", .{ .flags = .{
            .horizontal_scrollbar = true,
        } });
        defer imgui.endChild();

        _ = imgui.beginTabBar("buffer fields", .{});
        defer imgui.endTabBar();

        metadata: {
            if (static.selected <= 0) break :metadata;

            {
                if (imgui.beginTabItem("metadata", .{})) {
                    defer imgui.endTabItem();
                    imgui.text("id: {}", .{buffer.id});
                    imgui.text("File path: {s}", .{buffer.metadata.file_path});
                    imgui.text("File type: {s}", .{buffer.metadata.file_type});
                    imgui.text("Dirty: {}", .{buffer.metadata.dirty});
                    imgui.text("Dirty history: {}", .{buffer.metadata.history_dirty});
                    imgui.text("Last mod time: {}", .{buffer.metadata.file_last_mod_time});
                }
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
                    var array = (globals.ui.visiable_buffers_tree.root orelse break :selection).treeToArray(arena) catch break :selection;
                    for (array) |bw| if (bw.data.buffer.id == static.selected) break :blk &bw.data;
                    break :selection;
                };

                const selection = buffer.selection.get(buffer_window.cursor);
                const start = selection.start;
                const end = selection.end;
                imgui.text("start.row {} start.col {}", .{ start.row, start.col });
                imgui.text("end.row {} end.col {}", .{ end.row, end.col });

                if (imgui.button("regular", .{})) buffer_window.buffer.selection.kind = .regular;
                imgui.sameLine(.{});
                if (imgui.button("line", .{})) buffer_window.buffer.selection.kind = .line;
                imgui.sameLine(.{});
                if (imgui.button("block", .{})) buffer_window.buffer.selection.kind = .block;

                _ = imgui.beginChild("selection content", .{ .border = true, .flags = .{
                    .horizontal_scrollbar = true,
                } });
                defer imgui.endChild();

                // TODo: print differently when selection.kind.block is set
                var iter = Buffer.LineIterator.initRC(buffer, selection);
                while (iter.next()) |string| {
                    imgui.textUnformatted(string);
                    if (string[string.len - 1] != '\n') imgui.sameLine(.{ .spacing = 0 });
                }
            }
        }
    }
}
