const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const PieceTable = @This();

original: []const u8,
add: ArrayList(u8),

original_newlines: []u64,
add_newlines: ArrayList(u64),

size: u64,
newlines_count: u64,

pieces_root: *PieceNode,
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator, buf: []const u8) !PieceTable {
    var original_content = try allocator.alloc(u8, buf.len);
    var original_newlines = ArrayList(u64).init(allocator);

    @setRuntimeSafety(false);
    for (buf) |c, i| {
        original_content[i] = c;
        if (c == '\n')
            try original_newlines.append(i);
    }
    @setRuntimeSafety(true);

    var piece_table = PieceTable{
        .allocator = allocator,
        .original = original_content,
        .original_newlines = try original_newlines.toOwnedSlice(),
        .add = ArrayList(u8).init(allocator),
        .add_newlines = ArrayList(u64).init(allocator),
        .pieces_root = try allocator.create(PieceNode),
        .size = original_content.len,
        .newlines_count = 0,
    };
    piece_table.newlines_count = piece_table.original_newlines.len;
    original_newlines.deinit();

    piece_table.pieces_root.* = .{
        .source = .original,
        .start = 0,
        .len = buf.len,
        .newlines_start = 0,
        .newlines_count = piece_table.original_newlines.len,
    };

    return piece_table;
}

pub fn deinit(pt: *PieceTable) void {
    const allocator = pt.allocator;
    allocator.free(pt.original);
    allocator.free(pt.original_newlines);
    pt.add.deinit();
    pt.add_newlines.deinit();

    var root = pt.deinitTree(pt.pieces_root);
    if (root) |r| allocator.destroy(r);
}

pub fn deinitTree(pt: *PieceTable, piece: ?*PieceNode) ?*PieceNode {
    if (piece == null) return null;

    var left = pt.deinitTree(piece.?.left);
    if (left) |l| pt.allocator.destroy(l);
    var right = pt.deinitTree(piece.?.right);
    if (right) |r| pt.allocator.destroy(r);

    return piece.?;
}

pub fn insert(pt: *PieceTable, index: u64, string: []const u8) !void {
    var node_info = pt.findNode(index);
    var node = node_info.piece;
    var i = node_info.relative_index;

    var newlines_in_string_indices = ArrayList(u64).init(pt.allocator);
    defer newlines_in_string_indices.deinit();
    for (string) |c, ni|
        if (c == '\n')
            try newlines_in_string_indices.append(pt.add.items.len + ni);

    pt.splay(node);
    if (i > 0 and i < node.len) { // split
        var p1 = node;
        var p3 = try pt.allocator.create(PieceNode);

        var split_pieces = node.spilt(pt, i);

        split_pieces.right.parent = null;
        split_pieces.right.left = p1;
        split_pieces.right.right = p1.right;
        p3.* = split_pieces.right;
        if (p3.right) |p3_right| {
            p3_right.parent = p3;
            const subtree_info = p3_right.subtreeLengthAndNewlineCount();
            p3.left_subtree_len -= subtree_info.len;
            p3.left_subtree_newlines_count -= subtree_info.newlines_count;
        }

        split_pieces.left.parent = p3;
        split_pieces.left.left = p1.left;
        split_pieces.left.right = null;
        p1.* = split_pieces.left;

        pt.pieces_root = p3;

        try pt.prependToPiece(p3, string.len, newlines_in_string_indices.items.len);
    } else if (i == 0) {
        //
        try pt.prependToPiece(node, string.len, newlines_in_string_indices.items.len);
    } else {
        if (node.source == .add and node.start + node.len == pt.add.items.len and i >= node.len) {
            node.len += string.len;
            node.newlines_count += newlines_in_string_indices.items.len;
        } else {
            try pt.appendToPiece(node, string.len, newlines_in_string_indices.items.len);
        }
    }

    try pt.add.appendSlice(string);
    pt.size += string.len;
    if (newlines_in_string_indices.items.len > 0) {
        try pt.add_newlines.appendSlice(newlines_in_string_indices.items);
        pt.newlines_count += newlines_in_string_indices.items.len;
    }
}

pub fn delete(pt: *PieceTable, index: u64, num_to_delete: u64) !void {
    const allocator = pt.allocator;
    var len: u64 = 0;

    // Delete one byte at a time
    while (len < num_to_delete and index < pt.size) : (len += 1) {
        var node_info = pt.findNode(index);
        var node = node_info.piece;
        var i = node_info.relative_index;
        pt.splay(node);

        const byte_to_be_removed = pt.byteAt(index);
        if (i > 0 and i < node.len) { // split
            var split_piece = node.spilt(pt, i);
            var p1 = node;
            var p2 = try allocator.create(PieceNode);

            var right = split_piece.right;
            right.start += 1;
            right.len -= 1;

            right.parent = null;
            right.left = p1;
            right.right = p1.right;
            p2.* = right;
            if (p2.right) |p2_right| {
                p2_right.parent = p2;
                const subtree_info = p2_right.subtreeLengthAndNewlineCount();
                p2.left_subtree_len -= subtree_info.len;
                p2.left_subtree_newlines_count -= subtree_info.newlines_count;
            }

            split_piece.left.parent = p2;
            split_piece.left.left = p1.left;
            split_piece.left.right = null;
            p1.* = split_piece.left;

            if (byte_to_be_removed == '\n') {
                p2.newlines_start += 1;
                p2.newlines_count = if (p2.newlines_count == 0) 0 else p2.newlines_count - 1;
            }

            pt.pieces_root = p2;
            if (p2.len == 0) pt.removeRoot();
        } else {
            if (i == 0) node.start += 1; // delete beginning
            node.len -= 1;
            if (node.len == 0) {
                pt.removeRoot();
            } else if (byte_to_be_removed == '\n') {
                node.newlines_start += 1;
                node.newlines_count = if (node.newlines_count == 0) 0 else node.newlines_count - 1;
            }
        }

        pt.size -= 1;
        if (byte_to_be_removed == '\n') {
            pt.newlines_count -= 1;
        }
    }
}

pub fn byteAt(pt: *PieceTable, index: u64) u8 {
    var node_info = pt.findNode(index);
    var node = node_info.piece;
    var i = node_info.relative_index;
    return node.content(pt)[i];
}

pub fn getLine(pt: *PieceTable, allocator: std.mem.Allocator, line: u64) ![]u8 {
    var line_fragments = try pt.fragmentsOfLine(line);
    defer pt.allocator.free(line_fragments);
    return std.mem.concat(allocator, u8, line_fragments);
}

// TODO: Make it faster
pub fn getLines(pt: *PieceTable, allocator: std.mem.Allocator, first_line: u64, last_line: u64) ![]u8 {
    assert(last_line >= first_line);
    var fragments_of_lines = ArrayList([]const u8).init(pt.allocator);
    defer fragments_of_lines.deinit();
    var i: u64 = first_line;
    while (i <= last_line) : (i += 1) {
        var line_fragments = try pt.fragmentsOfLine(i);
        defer pt.allocator.free(line_fragments);
        try fragments_of_lines.appendSlice(line_fragments);
    }

    return std.mem.concat(allocator, u8, fragments_of_lines.items);
}

/// The contents of a line can be spread across multiple pieces,
/// this function returns an array of slices from all pieces that contain the contents of the line.
///
// A piece may contain content from multiple lines.
// If 1 or 2 nodes are returned, the nodes may have multiple lines.
// If 3 or more node are returned, the first and last may have multiple lines
// but nodes in-between will have the contents if the requested line.
pub fn fragmentsOfLine(pt: *PieceTable, line: u64) ![][]const u8 {
    var array_list = ArrayList(*PieceNode).init(pt.allocator);
    defer array_list.deinit();
    try pt.treeToArray(pt.pieces_root, &array_list);

    var relative_line = line;
    var lines_so_far: u64 = 0;
    var start: u64 = 0;
    var end: u64 = 0;
    for (array_list.items) |piece, i| {
        if (line >= lines_so_far and line <= lines_so_far + piece.newlines_count) {
            lines_so_far += piece.newlines_count;
            start = i;
            end = i + 1;

            var pieces = array_list.items;
            while (end < pieces.len and lines_so_far <= line) {
                lines_so_far += pieces[end].newlines_count;
                end += 1;
            }
            break;
        }

        lines_so_far += piece.newlines_count;
        relative_line -= piece.newlines_count;
    }

    var slice = array_list.items[start..end];
    var fragments = try pt.allocator.alloc([]const u8, slice.len);
    if (fragments.len == 1) {
        fragments[0] = slice[0].getLine(pt, relative_line);
    } else if (fragments.len == 2) {
        fragments[0] = slice[0].getLine(pt, slice[0].newlines_count);
        fragments[1] = slice[1].getLine(pt, 0);
    } else {
        for (fragments) |_, i| {
            if (i == 0)
                fragments[0] = slice[0].getLine(pt, slice[0].newlines_count)
            else if (i == fragments.len - 1)
                fragments[i] = slice[i].getLine(pt, 0)
            else
                fragments[i] = slice[i].content(pt);
        }
    }

    return fragments;
}

pub fn findNodeWithLine(pt: *PieceTable, newline_index_of_node: u64) struct {
    piece: *PieceNode,
    index: u64,
    newline_index: u64,
} {
    var piece = pt.pieces_root;
    var piece_index: u64 = 0;
    var piece_index_newline: u64 = 0;
    var relative_newline_index = newline_index_of_node;

    while (true) {
        if (relative_newline_index < piece.left_subtree_newlines_count) {
            if (piece.left) |left| {
                piece = left;
                continue;
            } else {
                piece_index_newline = piece_index;
                if (piece.newlines_count > 0) piece_index_newline += piece.relativeNewlineIndex(pt, relative_newline_index);
                break;
            }
        } else if (relative_newline_index >= piece.left_subtree_newlines_count and relative_newline_index < piece.left_subtree_newlines_count + piece.newlines_count) {
            relative_newline_index -= piece.left_subtree_newlines_count;
            piece_index += piece.left_subtree_len;
            piece_index_newline = piece_index;
            if (piece.newlines_count > 0) piece_index_newline += piece.relativeNewlineIndex(pt, relative_newline_index);
            break;
        } else {
            if (piece.right) |right| {
                relative_newline_index -= piece.left_subtree_newlines_count + piece.newlines_count;
                piece_index += piece.left_subtree_len + piece.len;
                piece = right;
                continue;
            } else {
                piece_index_newline = piece_index;
                if (piece.newlines_count > 0) piece_index_newline += piece.relativeNewlineIndex(pt, relative_newline_index);
                break;
            }
        }
    }

    return .{
        .piece = piece,
        .index = piece_index,
        .newline_index = piece_index_newline,
    };
}

fn splay(pt: *PieceTable, node: *PieceNode) void {
    while (node.parent != null) {
        if (node.parent.?.parent == null) { // parent is root
            node.zig();
        } else if (PieceNode.bothLeftChildOfGrandparent(node, node.parent.?) or
            PieceNode.bothRightChildOfGrandparent(node, node.parent.?))
        {
            node.zigZig();
        } else {
            node.zigZag();
        }
    }
    pt.pieces_root = node;
}

fn removeRoot(pt: *PieceTable) void {
    var root = pt.pieces_root;

    var node: *PieceNode = undefined;
    if (root.left) |left| {
        node = left.rightMostNode();

        if (left.right == null) {
            node.right = root.right;
            if (root.right) |rr| rr.parent = node;
            node.parent = null;
            pt.pieces_root = node;
            pt.allocator.destroy(root);
            return;
        }

        if (node.parent.? != root) node.parent.?.right = node.left;
        if (node.left) |l| l.parent = node.parent;
    } else if (root.right) |right| {
        node = right.leftMostNode();
        if (right.left == null) {
            node.parent = null;
            pt.pieces_root = node;
            pt.allocator.destroy(root);
            return;
        }
        node.bubbleUpChangedInfo(-@intCast(i64, node.len), -@intCast(i64, node.newlines_count));

        if (node.parent.? != root) node.parent.?.left = node.right;
        if (node.right) |r| r.parent = node.parent;
    } else {
        root.* = .{
            .parent = null,
            .left = null,
            .right = null,
            .left_subtree_len = 0,
            .left_subtree_newlines_count = 0,
            .newlines_start = 0,
            .newlines_count = 0,
            .start = 0,
            .len = 0,
            .source = root.source,
        };
        return;
    }

    var node_to_replace_root = PieceNode{
        .parent = null,
        .left = if (root.left != node) root.left else null,
        .right = if (root.right != node) root.right else null,
        .left_subtree_len = root.left_subtree_len,
        .left_subtree_newlines_count = root.left_subtree_newlines_count,

        .newlines_start = node.newlines_start,
        .newlines_count = node.newlines_count,
        .start = node.start,
        .len = node.len,
        .source = node.source,
    };

    if (root.left != null) {
        node_to_replace_root.left_subtree_len -= node.len;
        node_to_replace_root.left_subtree_newlines_count -= node.newlines_count;
    }

    root.* = node_to_replace_root;
    pt.allocator.destroy(node);
}

fn prependToPiece(pt: *PieceTable, piece: *PieceNode, string_len: u64, newlines_count_in_string: u64) !void {
    pt.splay(piece);

    var new_piece = try pt.allocator.create(PieceNode);
    new_piece.* = .{
        .parent = piece,
        .left = piece.left,
        .right = null,

        .left_subtree_len = piece.left_subtree_len,
        .left_subtree_newlines_count = piece.left_subtree_newlines_count,

        .newlines_start = pt.add_newlines.items.len,
        .newlines_count = newlines_count_in_string,

        .start = pt.add.items.len,
        .len = string_len,
        .source = .add,
    };

    piece.left = new_piece;
    piece.left_subtree_len += string_len;
    piece.left_subtree_newlines_count += newlines_count_in_string;

    if (new_piece.left) |np_left|
        np_left.parent = new_piece;
}

fn appendToPiece(pt: *PieceTable, piece: *PieceNode, string_len: u64, newlines_count_in_string: u64) !void {
    pt.splay(piece);
    var new_piece = try pt.allocator.create(PieceNode);
    new_piece.* = .{
        .parent = null, // will become the root
        .left = piece,
        .right = null,

        .left_subtree_len = pt.size,
        .left_subtree_newlines_count = pt.newlines_count,

        .newlines_start = pt.add_newlines.items.len,
        .newlines_count = newlines_count_in_string,

        .start = pt.add.items.len,
        .len = string_len,
        .source = .add,
    };

    piece.parent = new_piece;
    pt.pieces_root = new_piece;
}

pub fn printTreeTraverseTrace(pt: *PieceTable, node: ?*PieceNode) void {
    if (node == null) return;

    if (node.?.left) |left| {
        print("going left\n", .{});
        pt.printTreeTraverseTrace(left);
    }

    const n = node.?;
    print("ls={} lsnlc={}\ts={}..{} l={}\tnls={}..{} nlc={}\tso={}\n", .{
        n.left_subtree_len,
        n.left_subtree_newlines_count,

        n.start,
        n.start + n.len,
        n.len,

        n.newlines_start,
        n.newlines_start + n.newlines_count,
        n.newlines_count,

        n.source,
    });

    if (node.?.right) |right| {
        print("going right\n", .{});
        pt.printTreeTraverseTrace(right);
    }

    print("going up\n", .{});
}

pub fn buildIntoArrayList(pt: *PieceTable, node: ?*PieceNode, array_list: *ArrayList(u8)) std.mem.Allocator.Error!void {
    if (node == null) return;

    if (node.?.left) |left|
        try pt.buildIntoArrayList(left, array_list);

    try array_list.appendSlice(node.?.content(pt));

    if (node.?.right) |right|
        try pt.buildIntoArrayList(right, array_list);
}

pub fn buildIntoArray(pt: *PieceTable, array: []u8) []u8 {
    var start: u64 = 0;
    while (start < array.len) {
        var node = pt.findNode(start).piece;
        pt.splay(node);

        const content = node.content(pt);
        var slice = array[start..];
        if (slice.len >= content.len) {
            std.mem.copy(u8, slice, content);
            start += content.len;
        } else {
            std.mem.copy(u8, slice, content[0..slice.len]);
            start += slice.len;
            break;
        }
    }
    return array[0..start];
}

pub fn treeToArray(pt: *PieceTable, node: ?*PieceNode, array_list: *ArrayList(*PieceNode)) std.mem.Allocator.Error!void {
    if (node == null) return;

    if (node.?.left) |left|
        try pt.treeToArray(left, array_list);

    try array_list.append(node.?);

    if (node.?.right) |right|
        try pt.treeToArray(right, array_list);
}

pub fn findNode(pt: *PieceTable, index: u64) struct {
    piece: *PieceNode,
    relative_index: u64,
} {
    var node = pt.pieces_root;
    var relative_index = index;
    while (true) {
        if (relative_index < node.left_subtree_len and node.left != null) {
            node = node.left.?;
        } else if (relative_index >= node.left_subtree_len and relative_index < node.left_subtree_len + node.len) {
            relative_index -= node.left_subtree_len;
            break;
        } else {
            if (node.right) |right| {
                relative_index -= node.left_subtree_len + node.len;
                node = right;
                continue;
            } else break;
        }
    }
    return .{
        .piece = node,
        .relative_index = relative_index,
    };
}

const Source = enum(u1) {
    original,
    add,
};

pub const PieceNode = struct {
    parent: ?*PieceNode = null,
    left: ?*PieceNode = null,
    right: ?*PieceNode = null,

    left_subtree_len: u64 = 0,
    left_subtree_newlines_count: u64 = 0,

    newlines_start: u64 = 0,
    newlines_count: u64 = 0,

    start: u64,
    len: u64,
    source: Source,

    pub fn content(piece: *PieceNode, pt: *PieceTable) []const u8 {
        return switch (piece.source) {
            .original => pt.original[piece.start .. piece.start + piece.len],
            .add => pt.add.items[piece.start .. piece.start + piece.len],
        };
    }

    /// Returns the relative line within the piece, includes newline character if it's present.
    /// If a piece has no lines the entire content is returned.
    /// A line here can be a full line or part of a line from the text Buffer
    pub fn getLine(piece: *PieceNode, pt: *PieceTable, line: u64) []const u8 {
        if (piece.newlines_count == 0) return piece.content(pt);
        if (piece.len == 1 and piece.newlines_count == 1) {
            if (line == 0) return piece.content(pt) else return "";
        }

        var slice = piece.content(pt);
        var start: u64 = 0;
        var end: u64 = 0;

        if (line == 0) {
            start = 0;
            end = relativeNewlineIndex(piece, pt, 0) + 1;
        } else if (line >= piece.newlines_count) {
            start = relativeNewlineIndex(piece, pt, piece.newlines_count - 1) + 1;
            end = slice.len;
        } else {
            start = relativeNewlineIndex(piece, pt, line - 1) + 1;
            end = relativeNewlineIndex(piece, pt, line) + 1;
        }

        if (end >= slice.len) end = slice.len;
        if (start >= end) return "";

        return slice[start..end];
    }

    fn bothLeftChildOfGrandparent(node: *PieceNode, parent: *PieceNode) bool {
        return parent.left == node and parent.parent.?.left == parent;
    }

    fn bothRightChildOfGrandparent(node: *PieceNode, parent: *PieceNode) bool {
        return parent.right == node and parent.parent.?.right == parent;
    }

    pub fn subtreeLengthRecursive(node: *PieceNode) struct {
        len: u64,
        newlines_count: u64,
    } {
        var len: u64 = 0;
        var newlines_count: u64 = 0;

        if (node.left) |left| {
            var info = left.subtreeLengthRecursive();
            len += info.len;
            newlines_count += info.newlines_count;
        }

        len += node.len;
        newlines_count += node.newlines_count;

        if (node.right) |right| {
            var info = right.subtreeLengthRecursive();
            len += info.len;
            newlines_count += info.newlines_count;
        }

        return .{
            .len = len,
            .newlines_count = newlines_count,
        };
    }

    pub fn subtreeLengthAndNewlineCount(piece: *PieceNode) struct {
        len: u64,
        newlines_count: u64,
    } {
        var node: ?*PieceNode = piece;
        var len: u64 = 0;
        var newlines_count: u64 = 0;
        while (node) |n| {
            len += n.left_subtree_len + n.len;
            newlines_count += n.left_subtree_newlines_count + n.newlines_count;
            node = n.right;
        }

        return .{
            .len = len,
            .newlines_count = newlines_count,
        };
    }

    fn leftRotate(node: *PieceNode) void {
        if (node.parent == null) return;
        var parent = node.parent.?;
        var grand_parent = node.parent.?.parent;

        parent.right = node.left;
        parent.parent = node;
        if (parent.right) |right|
            right.parent = parent;

        node.left = parent;
        node.parent = grand_parent;

        const subtree_info = parent.subtreeLengthAndNewlineCount();
        node.left_subtree_len = subtree_info.len;
        node.left_subtree_newlines_count = subtree_info.newlines_count;

        if (grand_parent) |g| {
            if (g.right == parent)
                g.right = node
            else if (g.left == parent)
                g.left = node;
        }
    }

    fn rightRotate(node: *PieceNode) void {
        if (node.parent == null) return;
        var parent = node.parent.?;
        var grand_parent = node.parent.?.parent;

        parent.left = node.right;
        parent.parent = node;
        if (parent.left) |left| {
            left.parent = parent;
            const subtree_info = left.subtreeLengthAndNewlineCount();
            parent.left_subtree_len = subtree_info.len;
            parent.left_subtree_newlines_count = subtree_info.newlines_count;
        } else {
            parent.left_subtree_len = 0;
            parent.left_subtree_newlines_count = 0;
        }

        node.right = parent;
        node.parent = grand_parent;

        if (grand_parent) |g| {
            if (g.right == parent)
                g.right = node
            else if (g.left == parent)
                g.left = node;
        }

        if (node.left == null) {
            node.left_subtree_len = 0;
            node.left_subtree_newlines_count = 0;
        }
        if (parent.left == null) {
            parent.left_subtree_len = 0;
            parent.left_subtree_newlines_count = 0;
        }
    }

    fn zig(node: *PieceNode) void {
        if (node.parent == null) return;
        if (node.parent.?.left == node)
            node.rightRotate()
        else
            node.leftRotate();
    }

    fn zigZig(node: *PieceNode) void {
        if (node.parent == null) return;
        if (PieceNode.bothLeftChildOfGrandparent(node, node.parent.?)) {
            node.parent.?.rightRotate();
            node.rightRotate();
        } else if (PieceNode.bothRightChildOfGrandparent(node, node.parent.?)) {
            node.parent.?.leftRotate();
            node.leftRotate();
        }
    }

    fn zigZag(node: *PieceNode) void {
        // node is right of parent and parent is left of grandparent
        if (node.parent.?.right == node and node.parent.?.parent.?.left == node.parent.?) {
            node.leftRotate();
            node.rightRotate();
            // node is left of parent and parent is right of grandparent
        } else if (node.parent.?.left == node and node.parent.?.parent.?.right == node.parent.?) {
            node.rightRotate();
            node.leftRotate();
        }
    }

    fn isRightChild(node: *PieceNode) bool {
        if (node.parent) |parent| {
            return (node == parent.right);
        } else return false;
    }

    fn isLeftChild(node: *PieceNode) bool {
        if (node.parent) |parent| {
            return (node == parent.left);
        } else return false;
    }

    fn relativeNewlineIndex(piece: *PieceNode, pt: *PieceTable, newline_index: u64) u64 {
        assert(piece.newlines_count > 0);
        var newlines = switch (piece.source) {
            .original => pt.original_newlines,
            .add => pt.add_newlines.items,
        };

        var index = piece.newlines_start + newline_index;
        if (index >= newlines.len)
            index = newlines.len - 1;

        var res: u64 = 0;
        _ = @subWithOverflow(u64, newlines[index], piece.start, &res);
        return res;
    }

    fn bubbleUpChangedInfo(piece: *PieceNode, length: i64, newline_count: i64) void {
        var node = piece;
        while (node.parent) |parent| {
            if (node.isLeftChild()) {
                const len_result = @intCast(i64, parent.left_subtree_len) + length;
                const newlines_count_result = @intCast(i64, parent.left_subtree_newlines_count) + newline_count;

                parent.left_subtree_len = @intCast(u64, len_result);
                parent.left_subtree_newlines_count = @intCast(u64, newlines_count_result);
            }
            node = parent;
        }
    }

    pub fn rightMostNode(piece: *PieceNode) *PieceNode {
        var node = piece;
        while (node.right) |right| node = right;
        return node;
    }

    pub fn leftMostNode(piece: *PieceNode) *PieceNode {
        var node = piece;
        while (node.left) |left| node = left;
        return node;
    }

    fn newlineCountBeforeRelativeIndex(piece: *PieceNode, pt: *PieceTable, index: u64) u64 {
        var num: u64 = 0;
        while (num < piece.newlines_count) : (num += 1) {
            var relative_index = piece.relativeNewlineIndex(pt, num);
            if (relative_index >= index) break;
        }
        return num;
    }

    pub fn spilt(piece: *PieceNode, pt: *PieceTable, index: u64) struct {
        left: PieceNode,
        right: PieceNode,
    } {
        assert(index <= piece.len);
        const newlines_count_for_left = piece.newlineCountBeforeRelativeIndex(pt, index);

        var left = PieceNode{
            .parent = null,
            .left = null,
            .right = null,

            .left_subtree_len = piece.left_subtree_len,
            .left_subtree_newlines_count = piece.left_subtree_newlines_count,

            .newlines_start = piece.newlines_start,
            .newlines_count = newlines_count_for_left,

            .start = piece.start,
            .len = index,
            .source = piece.source,
        };

        var right = PieceNode{
            .parent = null,
            .left = null,
            .right = null,

            .left_subtree_len = if (piece.parent) |pp|
                pp.left_subtree_len
            else // piece is root. Need to adjust len later
                pt.size,

            .left_subtree_newlines_count = if (piece.parent) |pp|
                pp.left_subtree_newlines_count
            else // piece is root. Need to adjust len later
                pt.newlines_count,

            .newlines_start = piece.newlines_start + newlines_count_for_left,
            .newlines_count = piece.newlines_count - newlines_count_for_left,

            .start = piece.start + index,
            .len = piece.len - index,
            .source = piece.source,
        };

        if (piece.parent == null) {
            right.left_subtree_len -= right.len;
            right.left_subtree_newlines_count -= right.newlines_count;
        }

        return .{
            .left = left,
            .right = right,
        };
    }
};
