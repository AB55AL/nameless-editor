const std = @import("std");

const ts = @cImport(@cInclude("tree_sitter/api.h"));

const core = @import("../core.zig");
const StringTable = @import("../string_table.zig").StringTable;

pub const TreeSitterData = struct {
    pub const QueryData = struct {
        query: ?*Query,
        error_offset: u32 = 0,
        error_type: u32 = 0,
    };

    pub const Parser = ts.TSParser;
    pub const Query = ts.TSQuery;
    pub const Tree = ts.TSTree;

    pub const ParserMap = std.StringHashMapUnmanaged(*Parser);
    pub const QueriesTable = StringTable(QueryData);
    pub const TreeMap = std.AutoHashMapUnmanaged(core.BufferHandle, *Tree);
    pub const ThemeMap = std.StringHashMapUnmanaged(u32);
    pub const CaptureColor = struct { name: []const u8, color: u32 };

    parsers: ParserMap = .{},
    queries: QueriesTable = .{},
    trees: TreeMap = .{},
    themes: StringTable(ThemeMap) = .{},
    active_themes: std.StringHashMapUnmanaged([]const u8) = .{},
    allocator: std.mem.Allocator,

    pub fn init(allocator: std.mem.Allocator) TreeSitterData {
        // TODO: Hook up to editor.hooks
        return .{ .allocator = allocator };
    }

    pub fn deinit(self: *TreeSitterData) void {
        // zig fmt: off
        { var iter = self.parsers.valueIterator(); while (iter.next()) |parser| ts.ts_parser_delete(parser.*); }
        self.parsers.deinit(self.allocator);

        { var iter = self.queries.data.valueIterator(); while (iter.next()) |query_data| ts.ts_query_delete(query_data.query); }
        self.queries.data.deinit(self.allocator);

        { var iter = self.trees.valueIterator(); while (iter.next()) |tree| ts.ts_tree_delete(tree.*); }
        self.trees.deinit(self.allocator);

        { var iter = self.themes.data.valueIterator(); while (iter.next()) |theme| theme.deinit(self.allocator); }
        self.themes.data.deinit(self.allocator);

        self.active_themes.deinit(self.allocator);
        // zig fmt: on
    }

    pub fn createTree(self: *TreeSitterData, bhandle: core.BufferHandle, parser: *Parser) !?*Tree {
        _ = self;
        var input = ts.TSInput{
            .encoding = ts.TSInputEncodingUTF8,
            .payload = @as(*anyopaque, core.getBuffer(bhandle) orelse return null),
            .read = read,
        };

        var tree = ts.ts_parser_parse(parser, null, input);
        return tree;
    }

    pub fn updateTree(ptr: *anyopaque, buffer: *core.Buffer, bhandle: ?core.BufferHandle, change: core.Buffer.Change) void {
        var self = @ptrCast(*TreeSitterData, @alignCast(@alignOf(*TreeSitterData), ptr));
        const handle = bhandle orelse return;
        var tree = self.trees.get(handle) orelse return;
        var parser = self.parsers.get(buffer.metadata.buffer_type) orelse return;

        var input = ts.TSInput{
            .encoding = ts.TSInputEncodingUTF8,
            .payload = @as(*anyopaque, core.getBuffer(bhandle.?) orelse return),
            .read = read,
        };

        var ts_edit = toTSInputEdit(buffer, change);
        ts.ts_tree_edit(tree, &ts_edit);
        // TODO: Incrementally parse the tree
        var new_tree = ts.ts_parser_parse(parser, null, input);

        if (new_tree) |nt| {
            self.trees.getPtr(handle).?.* = nt;
            ts.ts_tree_delete(tree);
        }
    }

    pub fn hookUpToEditorHooks(self: *TreeSitterData, hooks: *core.hooks.EditorHooks) void {
        _ = hooks.createAndAttach(.after_insert, self, updateTree) catch return;
        _ = hooks.createAndAttach(.after_delete, self, updateTree) catch return;
    }

    pub fn read(payload: ?*anyopaque, index: u32, pos: ts.TSPoint, bytes_read: [*c]u32) callconv(.C) [*c]const u8 {
        _ = pos;
        var buffer = @ptrCast(*core.Buffer, @alignCast(@alignOf(*core.Buffer), payload.?));

        if (index >= buffer.size()) {
            bytes_read.* = 0;
            return "";
        }

        var node_info = buffer.lines.tree.findNode(index);
        const content = node_info.piece.content(&buffer.lines);
        bytes_read.* = @truncate(u32, content.len);
        return content.ptr;
    }

    pub fn toTSPoint(point: core.Buffer.Point) ts.TSPoint {
        return .{ .row = @truncate(u32, point.row - 1), .column = @truncate(u32, point.col - 1) };
    }

    pub fn toTSInputEdit(buffer: *core.Buffer, change: core.Buffer.Change) ts.TSInputEdit {
        // zig fmt: off
        const start_byte = change.start_index;
        const start_point = change.start_point;
        const old_end_byte = start_byte + change.delete_len;
        const new_end_byte = start_byte + change.inserted_len;
        const old_end_point = buffer.getPoint(old_end_byte);
        const new_end_point = buffer.getPoint(new_end_byte);

        return ts.TSInputEdit{
            .start_byte = @truncate(u32, start_byte), .old_end_byte = @truncate(u32, old_end_byte), .new_end_byte = @truncate(u32, new_end_byte),
            .start_point = toTSPoint(start_point), .old_end_point = toTSPoint(old_end_point), .new_end_point = toTSPoint(new_end_point),
        };
        // zig fmt: on
    }

    pub const BufferDisplayer = struct {
        const Self = BufferDisplayer;

        const RangeSet = std.AutoHashMapUnmanaged(core.Buffer.Range, core.BufferDisplayer.ColorRange);
        const RowInfoSet = std.AutoHashMap(u64, *RangeSet);

        tree_sitter: *TreeSitterData,

        pub fn interface(self: *Self) core.BufferDisplayer {
            return .{ .ptr = @ptrCast(*anyopaque, @alignCast(1, self)), .get_fn = get };
        }

        pub fn get(ptr: *anyopaque, arena: std.mem.Allocator, buffer_window: *core.BufferWindow, buffer: *core.Buffer, window_height: f32) std.mem.Allocator.Error![]core.BufferDisplayer.RowInfo {
            var self = @ptrCast(*Self, @alignCast(@alignOf(*Self), ptr));
            _ = window_height;

            var tree_sitter = self.tree_sitter;

            var rows_info = RowInfoSet.init(arena);

            // TODO: Create query and tree instead of returning an empty slice
            var tree = tree_sitter.trees.get(buffer_window.bhandle);
            var query_data = tree_sitter.queries.get(buffer.metadata.buffer_type, "highlight") orelse return &.{};

            var root = ts.ts_tree_root_node(tree);
            if (ts.ts_node_is_null(root)) return &.{};

            var qc = ts.ts_query_cursor_new();
            const start_byte = @intCast(u32, buffer.indexOfFirstByteAtRow(buffer_window.first_visiable_row));
            const end_byte = @intCast(u32, buffer.size());
            ts.ts_query_cursor_set_byte_range(qc, start_byte, end_byte);
            ts.ts_query_cursor_exec(qc, query_data.query, root);

            var match: ts.TSQueryMatch = undefined;
            while (ts.ts_query_cursor_next_match(qc, &match)) {
                if (match.capture_count <= 0) continue;

                var captures = match.captures[0..match.capture_count];
                for (captures) |cap| {
                    var sp = ts.ts_node_start_point(cap.node);
                    var ep = ts.ts_node_end_point(cap.node);
                    _ = ep;
                    var si = ts.ts_node_start_byte(cap.node);
                    var ei = ts.ts_node_end_byte(cap.node);

                    var len: u32 = 0;
                    const slice = ts.ts_query_capture_name_for_id(query_data.query, cap.index, &len);
                    const name = slice[0..len];

                    const active_theme = tree_sitter.active_themes.get(buffer.metadata.buffer_type) orelse "";
                    const theme = tree_sitter.themes.get(buffer.metadata.buffer_type, active_theme);
                    const color = if (theme) |th| th.get(name) orelse 0xFFFFFFFF else 0xFFFFFFFF;

                    var range = bufferRange(si, ei);
                    var range_set = try getOrCreateRangeSet(&rows_info, sp.row + 1); // offset to be 1-based
                    const exists = range_set.get(range);
                    if (exists == null and !partiallyOverlaps(range, range_set)) {
                        var v = core.BufferDisplayer.ColorRange{ .start = buffer.offsetIndexToLine(si), .end = buffer.offsetIndexToLine(ei), .color = color };
                        try range_set.put(arena, range, v);
                    }
                }
            }

            return rowInfoSetToSlice(arena, &rows_info);
        }

        fn getOrCreateRangeSet(rows_info: *RowInfoSet, row: u64) !*RangeSet {
            const allocator = rows_info.allocator;
            var range_set = rows_info.get(row) orelse blk: {
                var rs = try allocator.create(RangeSet);
                rs.* = RangeSet{};
                try rows_info.put(row, rs);
                break :blk rs;
            };

            return range_set;
        }

        fn partiallyOverlaps(range: core.Buffer.Range, set: *RangeSet) bool {
            var iter = set.keyIterator();
            while (iter.next()) |kp| {
                if (range.overlaps(kp.*) and range.start != kp.end) {
                    // a range's start is allowed to overlap with the end of a another range
                    return true;
                }
            }

            return false;
        }

        fn rowInfoSetToSlice(allocator: std.mem.Allocator, set: *RowInfoSet) ![]core.BufferDisplayer.RowInfo {
            var row_info = try allocator.alloc(core.BufferDisplayer.RowInfo, set.count());
            var row_iter = set.iterator();
            var i: u64 = 0;
            while (row_iter.next()) |kp| {
                const row = kp.key_ptr.*;
                const ranges_slice = try rangeSetToSlice(allocator, kp.value_ptr.*);
                const size: f32 = -1;
                row_info[i] = .{ .row = row, .color_ranges = ranges_slice, .size = size };
                i += 1;
            }

            return row_info;
        }

        fn rangeSetToSlice(allocator: std.mem.Allocator, set: *RangeSet) ![]core.BufferDisplayer.ColorRange {
            var slice = try allocator.alloc(core.BufferDisplayer.ColorRange, set.count());
            var iter = set.valueIterator();
            var i: u64 = 0;
            while (iter.next()) |cr| {
                slice[i] = cr.*;
                i += 1;
            }

            return slice;
        }

        fn bufferRange(start: u32, end: u32) core.Buffer.Range {
            return .{ .start = start, .end = end };
        }
    };
};
