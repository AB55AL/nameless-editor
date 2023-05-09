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
    pub const StringSet = std.StringHashMapUnmanaged(void);
    pub const TreeMap = std.AutoHashMapUnmanaged(core.BufferHandle, *Tree);
    pub const ThemeMap = std.StringHashMapUnmanaged(u32);
    pub const CaptureColor = struct { name: []const u8, color: u32 };

    parsers: ParserMap = .{},
    queries: QueriesTable = .{},
    trees: TreeMap = .{},
    strings: StringSet = .{},
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

        { var iter = self.strings.keyIterator(); while (iter.next()) |string| self.allocator.free(string.*); }
        self.strings.deinit(self.allocator);

        self.active_themes.deinit(self.allocator);
        // zig fmt: on
    }

    pub fn putParser(self: *TreeSitterData, file_type: []const u8, parser: *Parser) !void {
        const ft = try self.getAndPutString(file_type);
        try self.parsers.put(self.allocator, ft, parser);
    }

    pub fn getParser(self: *TreeSitterData, file_type: []const u8) ?*Parser {
        return self.parsers.get(file_type);
    }

    pub fn putQuery(self: *TreeSitterData, file_type: []const u8, query_name: []const u8, query_data: QueryData) !void {
        const ft = try self.getAndPutString(file_type);
        const qn = try self.getAndPutString(query_name);
        try self.queries.put(self.allocator, ft, qn, query_data);
    }

    pub fn getQuery(self: *TreeSitterData, file_type: []const u8, query_name: []const u8) ?QueryData {
        return self.queries.get(file_type, query_name);
    }

    pub fn putTree(self: *TreeSitterData, bhandle: core.BufferHandle, tree: *Tree) !void {
        try self.trees.put(self.allocator, bhandle, tree);
    }

    pub fn getTree(self: *TreeSitterData, bhandle: core.BufferHandle) ?*Tree {
        return self.trees.get(bhandle);
    }

    pub fn putTheme(self: *TreeSitterData, file_type: []const u8, theme_name: []const u8, theme: []CaptureColor) !void {
        const ft = try self.getAndPutString(file_type);
        const tn = try self.getAndPutString(theme_name);

        var theme_copy = ThemeMap{};
        errdefer theme_copy.deinit(self.allocator);
        for (theme) |cc| {
            const ts_capture_name = try self.getAndPutString(cc.name);
            try theme_copy.put(self.allocator, ts_capture_name, cc.color);
        }
        try self.themes.put(self.allocator, ft, tn, theme_copy);
    }

    pub fn getTheme(self: *TreeSitterData, file_type: []const u8, theme_name: []const u8) ?*ThemeMap {
        return self.themes.data.getPtr(.{ file_type, theme_name });
    }

    pub fn getActiveTheme(self: *TreeSitterData, file_type: []const u8) ?[]const u8 {
        return self.active_themes.get(file_type);
    }

    pub fn setActiveTheme(self: *TreeSitterData, file_type: []const u8, theme_name: []const u8) !void {
        const theme_exits = self.themes.data.getKey(.{ file_type, theme_name }) != null;
        if (theme_exits) {
            const ft = try self.getAndPutString(file_type);
            const tn = try self.getAndPutString(theme_name);
            try self.active_themes.put(self.allocator, ft, tn);
        }
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

    fn getAndPutString(self: *TreeSitterData, string: []const u8) ![]const u8 {
        var gop = try self.strings.getOrPut(self.allocator, string);
        if (!gop.found_existing) gop.key_ptr.* = try core.utils.newSlice(self.allocator, string);
        return gop.key_ptr.*;
    }

    fn read(payload: ?*anyopaque, index: u32, pos: ts.TSPoint, bytes_read: [*c]u32) callconv(.C) [*c]const u8 {
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
};
