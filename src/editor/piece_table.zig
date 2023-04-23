const std = @import("std");
const print = std.debug.print;
const ArrayList = std.ArrayList;
const assert = std.debug.assert;

const utils = @import("../utils.zig");

const PieceTable = @This();

original: []const u8,
add: ArrayList(u8),

original_newlines: []u64,
add_newlines: ArrayList(u64),

tree: SplayTree,

pub fn init(allocator: std.mem.Allocator, buf: []const u8) !PieceTable {
    var original_content = try allocator.alloc(u8, buf.len);
    var original_newlines = ArrayList(u64).init(allocator);

    @setRuntimeSafety(false);
    for (buf, 0..) |c, i| {
        original_content[i] = c;
        if (c == '\n')
            try original_newlines.append(i);
    }
    @setRuntimeSafety(true);

    var piece_table = PieceTable{
        .original = original_content,
        .original_newlines = try original_newlines.toOwnedSlice(),
        .add = ArrayList(u8).init(allocator),
        .add_newlines = ArrayList(u64).init(allocator),

        .tree = .{
            .root = null,
            .size = original_content.len,
            .newlines_count = 0,
        },
    };
    piece_table.tree.newlines_count = piece_table.original_newlines.len;
    original_newlines.deinit();

    if (buf.len > 0) {
        var root = try allocator.create(PieceNode);
        root.* = .{
            .source = .original,
            .start = 0,
            .len = buf.len,
            .newlines_start = 0,
            .newlines_count = piece_table.original_newlines.len,
        };

        piece_table.tree.root = root;
    }

    return piece_table;
}

pub fn deinit(pt: *PieceTable, allocator: std.mem.Allocator) void {
    allocator.free(pt.original);
    allocator.free(pt.original_newlines);
    pt.add.deinit();
    pt.add_newlines.deinit();

    var root = PieceNode.deinitTree(pt.tree.root, allocator);
    if (root) |r| allocator.destroy(r);
}

pub fn insert(pt: *PieceTable, allocator: std.mem.Allocator, index: u64, string: []const u8) !void {
    var newlines_in_string_indices = ArrayList(u64).init(allocator);
    defer newlines_in_string_indices.deinit();
    for (string, 0..) |c, ni|
        if (c == '\n')
            try newlines_in_string_indices.append(pt.add.items.len + ni);

    try pt.add.ensureUnusedCapacity(string.len);
    try pt.add_newlines.ensureUnusedCapacity(newlines_in_string_indices.items.len);

    var new_tree = SplayTree{};
    if (pt.tree.root != null) {
        var node_info = pt.tree.findNode(index);
        var node = node_info.piece;
        var i = node_info.relative_index;
        pt.tree.splay(node);
        const is_last_node = pt.tree.isLastNode(node);
        const is_first_node = pt.tree.isFirstNode(node);
        if (node.source == .add and node.start + node.len == pt.add.items.len and i >= node.len) {
            // modify the piece
            node.len += string.len;
            node.newlines_count += newlines_in_string_indices.items.len;
            pt.tree.size += string.len;
            pt.tree.newlines_count += newlines_in_string_indices.items.len;
        } else {
            var new_piece = try pt.newAddPiece(allocator, string.len, newlines_in_string_indices.items.len);
            pt.tree.removeNode(node);

            if (i > 0 and i < node.len) { // split

                var right_piece = try allocator.create(PieceNode);
                errdefer allocator.destroy(right_piece);

                const split_piece = node.split(pt, i);
                node.* = split_piece.left.toPiece();
                right_piece.* = split_piece.right.toPiece();

                new_tree.setAsNewTree(node.toTree());
                new_tree.append(new_piece);
                new_tree.append(right_piece);
                new_tree.splay(node);

                new_tree.destroyIfEmpty(allocator, node);
                new_tree.destroyIfEmpty(allocator, new_piece);
                new_tree.destroyIfEmpty(allocator, right_piece);
            } else {
                new_tree.setAsNewTree(node.toTree());

                if (i == 0)
                    new_tree.prepend(new_piece)
                else
                    new_tree.append(new_piece);

                new_tree.splay(node);
            }
        }

        if (pt.tree.root == null) {
            pt.tree.setAsNewTree(new_tree);
        } else if (is_last_node) { // append to tree
            pt.tree.appendTree(new_tree);
        } else if (is_first_node) {
            pt.tree.prependTree(new_tree);
        } else if (new_tree.root != null) {
            const insert_index = (index - node_info.relative_index);
            var ni = pt.tree.findNode(insert_index);
            var n = ni.piece;
            pt.tree.insertBeforeTree(n, new_tree);
        }
    } else {
        var new_piece = try pt.newAddPiece(allocator, string.len, newlines_in_string_indices.items.len);
        pt.tree.setAsNewTree(new_piece.toTree());
    }

    pt.add.appendSliceAssumeCapacity(string);
    pt.add_newlines.appendSliceAssumeCapacity(newlines_in_string_indices.items);
}

pub fn delete(pt: *PieceTable, allocator: std.mem.Allocator, start_index: u64, end_index: u64) !void {
    var start_node_info = pt.tree.findNode(start_index);
    var end_node_info = pt.tree.findNode(end_index);

    var start_node = start_node_info.piece;
    var end_node = end_node_info.piece;
    var new_node = try allocator.create(PieceNode);

    pt.tree.splay(start_node);
    const is_last_node = pt.tree.isLastNode(start_node) or pt.tree.isLastNode(end_node);
    const is_first_node = pt.tree.isFirstNode(start_node);

    // extarct the middle tree holding all nodes between start_node and end_node (inclusive)
    var new_tree = pt.tree.splitLeftAndRight(start_node, end_node);

    const left = start_node.split(pt, start_node_info.relative_index).left;
    const right = end_node.split(pt, end_node_info.relative_index + 1).right;

    if (start_node == end_node) {
        start_node.* = left.toPiece();
        new_node.* = right.toPiece();

        new_tree.setAsNewTree(start_node.toTree());
        new_tree.append(new_node);

        new_tree.destroyIfEmpty(allocator, start_node);
        new_tree.destroyIfEmpty(allocator, new_node);
    } else {
        new_tree.removeNode(start_node);
        new_tree.removeNode(end_node);

        var tree_of_deleted_nodes = new_tree;

        start_node.* = left.toPiece();
        end_node.* = right.toPiece();

        new_tree = SplayTree{};
        new_tree.append(start_node);
        new_tree.append(end_node);

        new_tree.destroyIfEmpty(allocator, start_node);
        new_tree.destroyIfEmpty(allocator, end_node);
        allocator.destroy(new_node);

        if (tree_of_deleted_nodes.root != null) {
            while (true) {
                var n = tree_of_deleted_nodes.root orelse break;
                tree_of_deleted_nodes.removeNode(n);
                allocator.destroy(n);
            }
        }
    }

    if (pt.tree.root == null) {
        pt.tree.setAsNewTree(new_tree);
    } else if (is_last_node) { // append to tree
        pt.tree.appendTree(new_tree);
    } else if (is_first_node) {
        pt.tree.prependTree(new_tree);
    } else if (new_tree.root != null) {
        const insert_index = (start_index - start_node_info.relative_index);
        var ni = pt.tree.findNode(insert_index);
        var n = ni.piece;
        pt.tree.insertBeforeTree(n, new_tree);
    }
}

pub fn byteAt(pt: *PieceTable, index: u64) u8 {
    var node_info = pt.tree.findNode(index);
    return node_info.piece.content(pt)[node_info.relative_index];
}

pub fn newAddPiece(pt: *PieceTable, allocator: std.mem.Allocator, string_len: u64, newlines_in_string: u64) !*PieceNode {
    var new_piece = try allocator.create(PieceNode);
    new_piece.* = .{
        .newlines_start = pt.add_newlines.items.len,
        .newlines_count = newlines_in_string,

        .start = pt.add.items.len,
        .len = string_len,
        .source = .add,
    };

    return new_piece;
}

const Source = enum(u1) {
    original,
    add,

    pub fn toString(source: Source) []const u8 {
        return switch (source) {
            .add => "add",
            .original => "org",
        };
    }
};

pub const SplayTree = struct {
    root: ?*PieceNode = null,
    size: u64 = 0,
    newlines_count: u64 = 0,

    pub fn destroyIfEmpty(tree: *SplayTree, allocator: std.mem.Allocator, node: *PieceNode) void {
        if (node.len > 0) return;

        tree.removeNode(node);
        allocator.destroy(node);
    }

    pub fn insertAfter(tree: *SplayTree, node: *PieceNode, new_node: *PieceNode) void {
        utils.assert(new_node.len > 0, "");
        var right_subtree = tree.splitRightTree(node);

        var left_subtree = SplayTree{
            .root = node,
            .size = tree.size,
            .newlines_count = tree.newlines_count,
        };

        tree.root = new_node;
        tree.size = new_node.len;
        tree.newlines_count = new_node.newlines_count;

        tree.setAsLeftSubTree(new_node, left_subtree);
        if (right_subtree.root != null)
            tree.setAsRightSubTree(new_node, right_subtree);
    }

    pub fn insertBefore(tree: *SplayTree, node: *PieceNode, new_node: *PieceNode) void {
        utils.assert(new_node.len > 0, "");

        tree.splay(node);
        if (node.previousNode()) |p| {
            tree.insertAfter(p, new_node);
        } else { // left is null
            tree.setAsLeftSubTree(node, new_node.toTree());
        }
    }

    pub fn insertAfterTree(tree: *SplayTree, node: *PieceNode, new_tree: SplayTree) void {
        var right_st = tree.splitRightTree(node);
        tree.setAsRightSubTree(node, new_tree);
        tree.appendTree(right_st);
    }

    pub fn insertBeforeTree(tree: *SplayTree, node: *PieceNode, new_tree: SplayTree) void {
        var left_st = tree.splitLeftTree(node);
        tree.setAsLeftSubTree(node, new_tree);
        tree.prependTree(left_st);
    }

    pub fn append(tree: *SplayTree, new_node: *PieceNode) void {
        if (tree.root == null)
            tree.setAsNewTree(new_node.toTree())
        else
            tree.appendTree(new_node.toTree());
    }

    pub fn prepend(tree: *SplayTree, new_node: *PieceNode) void {
        if (tree.root == null)
            tree.setAsNewTree(new_node.toTree())
        else {
            var left_most = tree.root.?.leftMostNode();
            tree.insertBefore(left_most, new_node);
        }
    }

    /// Splay the largest node then set _subtree_ to be the right subtree
    pub fn appendTree(tree: *SplayTree, subtree: SplayTree) void {
        if (subtree.root == null) return;

        if (tree.root == null) {
            tree.setAsNewTree(subtree);
        } else if (tree.root != null) {
            var biggest_node = tree.root.?.rightMostNode();
            tree.splay(biggest_node);

            utils.assert(tree.root.?.right == null, "");

            tree.setAsRightSubTree(tree.root.?, subtree);
        }
    }

    pub fn prependTree(tree: *SplayTree, new_tree: SplayTree) void {
        if (new_tree.root == null) return;

        if (tree.root == null) {
            tree.setAsNewTree(new_tree);
        } else {
            var first = tree.findNode(0).piece;
            tree.splay(first);
            tree.setAsLeftSubTree(first, new_tree);
        }
    }

    /// Tries to insert new_node after previous_node
    /// otherwise inserts before next_node
    /// otherwise inserts before the tree root
    pub fn insertBeforeOrAfter(tree: *SplayTree, previous_node: ?*PieceNode, next_node: ?*PieceNode, new_node: *PieceNode) void {
        utils.assert(new_node.len > 0, "");
        if (previous_node) |pn| {
            tree.insertAfter(pn, new_node);
        } else if (next_node) |nn| {
            tree.insertBefore(nn, new_node);
        } else if (tree.root) |root| {
            tree.insertBefore(root, new_node);
        } else {
            tree.setAsNewTree(new_node.toTree());
        }
    }

    pub fn removeNode(tree: *SplayTree, node: *PieceNode) void {
        var left_st = tree.splitLeftTree(node);
        var right_st = tree.splitRightTree(node);

        tree.* = SplayTree{};
        tree.appendTree(left_st);
        tree.appendTree(right_st);

        // reset tree related data
        node.* = node.pieceInfo().toPiece();
    }

    pub fn findNode(tree: *SplayTree, index: u64) struct {
        piece: *PieceNode,
        relative_index: u64,
    } {
        utils.assert(tree.root != null, "");

        var i = index;

        var node = tree.root.?;
        while (true) {
            if (i < node.left_subtree_len) {
                node = node.left.?;
            } else if (i >= node.left_subtree_len and i < node.left_subtree_len + node.len) {
                // found it
                i -= node.left_subtree_len;
                break;
            } else if (node.right) |right| {
                i -= node.left_subtree_len + node.len;
                node = right;
            } else {
                break;
            }
        }

        tree.splay(node);
        return .{
            .piece = node,
            .relative_index = i,
        };
    }

    pub fn findNodeWithLine(tree: *SplayTree, pt: *const PieceTable, newline_index_of_node: u64) struct {
        piece: *PieceNode,
        newline_index: u64, // absolute
    } {
        utils.assert(newline_index_of_node <= tree.newlines_count, "newline_index_of_node cannot be greater than the total newlines in the table");
        utils.assert(tree.root != null, "pieces_root must not be null");

        var node = tree.root.?;
        var i = newline_index_of_node;

        var abs_nl_index: u64 = 0;

        while (true) {
            if (i < node.left_subtree_newlines_count) {
                node = node.left.?;
            } else if (i >= node.left_subtree_newlines_count and i < node.left_subtree_newlines_count + node.newlines_count) {
                // found it
                i -= node.left_subtree_newlines_count;
                abs_nl_index += node.left_subtree_len;
                break;
            } else if (node.right) |right| {
                i -= node.left_subtree_newlines_count + node.newlines_count;
                abs_nl_index += node.left_subtree_len + node.len;
                node = right;
            } else break;
        }

        if (node.newlines_count > 0) abs_nl_index += node.relativeNewlineIndex(pt, i);

        tree.splay(node);
        return .{
            .piece = node,
            .newline_index = abs_nl_index,
        };
    }

    fn isLastNode(tree: *SplayTree, node: *PieceNode) bool {
        if (tree.root) |root|
            return node == root.rightMostNode()
        else
            return false;
    }

    fn isFirstNode(tree: *SplayTree, node: *PieceNode) bool {
        if (tree.root) |root|
            return node == root.leftMostNode()
        else
            return false;
    }

    fn splay(tree: *SplayTree, node: *PieceNode) void {
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
        tree.root = node;
    }

    fn splitRightTree(tree: *SplayTree, node: *PieceNode) SplayTree {
        tree.splay(node);

        if (node.right == null) return SplayTree{};

        var right_subtree_root = node.right;
        var subtree_size = node.rightSubTreeSize(.{
            .size = tree.size,
            .newlines_count = tree.newlines_count,
        });

        node.right = null;
        if (right_subtree_root) |rsr| rsr.parent = null;

        tree.size -|= subtree_size.size;
        tree.newlines_count -|= subtree_size.newlines_count;

        return .{
            .root = right_subtree_root,
            .size = subtree_size.size,
            .newlines_count = subtree_size.newlines_count,
        };
    }

    fn splitLeftTree(tree: *SplayTree, node: *PieceNode) SplayTree {
        tree.splay(node);

        if (node.left == null) return SplayTree{};

        var left_subtree_root = node.left;
        node.left = null;

        var subtree_size = PieceNode.Size{};
        if (left_subtree_root) |lsr| {
            lsr.parent = null;
            subtree_size = .{
                .size = node.left_subtree_len,
                .newlines_count = node.left_subtree_newlines_count,
            };
        }

        node.left_subtree_newlines_count = 0;
        node.left_subtree_len = 0;

        tree.size -|= subtree_size.size;
        tree.newlines_count -|= subtree_size.newlines_count;

        return .{
            .root = left_subtree_root,
            .size = subtree_size.size,
            .newlines_count = subtree_size.newlines_count,
        };
    }

    fn splitLeftAndRight(tree: *SplayTree, left_node: *PieceNode, right_node: *PieceNode) SplayTree {
        {
            var lr = left_node.rootOfNode();
            var rr = right_node.rootOfNode();
            utils.assert(lr == rr or left_node == rr or right_node == lr, "left and right nodes must be in the same tree");
        }

        if (left_node == right_node) {
            tree.removeNode(left_node);
            return left_node.toTree();
        } else {
            var left_st = tree.splitLeftTree(left_node);
            var right_st = tree.splitRightTree(right_node);

            var middle_tree = tree.*;

            left_st.appendTree(right_st);
            tree.setAsNewTree(left_st);

            return middle_tree;
        }
    }

    pub fn deinitAndSetAsNewTree(tree: *SplayTree, allocator: std.mem.Allocator, new_tree: SplayTree) void {
        var old_root = PieceNode.deinitTree(tree.root, allocator);
        if (old_root) |r| allocator.destroy(r);

        tree.setAsNewTree(new_tree);
    }

    fn setAsNewTree(tree: *SplayTree, subtree: SplayTree) void {
        if (subtree.root) |root| utils.assert(root.parent == null, "");
        tree.root = subtree.root;
        tree.size = subtree.size;
        tree.newlines_count = subtree.newlines_count;
    }

    fn setAsLeftSubTree(tree: *SplayTree, node: *PieceNode, subtree: SplayTree) void {
        utils.assert(node.left == null, "");
        tree.splay(node);
        if (subtree.root == null) return;

        node.left = subtree.root;
        node.left_subtree_len = subtree.size;
        node.left_subtree_newlines_count = subtree.newlines_count;

        subtree.root.?.parent = node;

        tree.size += subtree.size;
        tree.newlines_count += subtree.newlines_count;
    }

    fn setAsRightSubTree(tree: *SplayTree, node: *PieceNode, subtree: SplayTree) void {
        utils.assert(node.right == null, "");
        tree.splay(node);
        if (subtree.root == null) return;

        node.right = subtree.root;
        subtree.root.?.parent = node;

        tree.size += subtree.size;
        tree.newlines_count += subtree.newlines_count;
    }

    pub fn treeDepth(tree: *SplayTree) u32 {
        const helper = struct {
            fn f(node: *PieceNode, level: u32) u32 {
                const left = if (node.left) |left| f(left, level + 1) else level;
                const right = if (node.right) |right| f(right, level + 1) else level;
                return std.math.max(left, right);
            }
        }.f;
        return if (tree.root) |root| helper(root, 0) + 1 else 0;
    }

    pub fn printTreeOrdered(tree: *SplayTree, pt: ?*PieceTable, allocator: std.mem.Allocator) !void {
        var al = ArrayList(*PieceNode).init(allocator);
        defer al.deinit();
        tree.treeToArray(tree.root, &al) catch unreachable;
        for (al.items) |n| {
            n.print(false);
            if (pt) |p| std.debug.print("{any}", .{n.content(p)});

            std.debug.print("\n", .{});
        }
    }

    pub fn printTreeTraverseTrace(tree: *SplayTree, pt: *const PieceTable) void {
        const helper = struct {
            fn recurse(s_tree: *SplayTree, piece_table: *const PieceTable, node: ?*PieceNode) void {
                if (node == null) return;

                if (node.?.left) |left| {
                    print("going left\n", .{});
                    s_tree.recurse(piece_table, left);
                }

                const n = node.?;
                n.print(true);
                if (node.?.right) |right| {
                    print("going right\n", .{});
                    s_tree.recurse(piece_table, right);
                }

                print("going up\n", .{});
            }
        };

        std.debug.print("( TREE START\n", .{});
        helper.recurse(tree, pt, tree.roor);
        std.debug.print("TREE END )\n", .{});
    }

    pub fn treeToArray(tree: *SplayTree, node: ?*PieceNode, array_list: *ArrayList(*PieceNode)) std.mem.Allocator.Error!void {
        if (node == null) return;

        if (node.?.left) |left|
            try tree.treeToArray(left, array_list);

        try array_list.append(node.?);

        if (node.?.right) |right|
            try tree.treeToArray(right, array_list);
    }

    pub fn piecesCount(tree: *SplayTree) u64 {
        const helper = struct {
            fn recurse(t: *SplayTree, piece: ?*PieceNode, count: *u64) void {
                if (piece == null) return;

                if (piece.?.left) |left|
                    recurse(t, left, count);

                count.* += 1;

                if (piece.?.right) |right|
                    recurse(t, right, count);
            }
        };

        if (tree.root == null) return 0;
        var res: u64 = 0;
        helper.recurse(tree, tree.root, &res);
        return res;
    }

    pub fn treeToPieceInfoArray(tree: *SplayTree, allocator: std.mem.Allocator) ![]const PieceNode.Info {
        const helper = struct {
            fn recurse(t: *SplayTree, node: ?*PieceNode, array_list: *ArrayList(PieceNode.Info)) std.mem.Allocator.Error!void {
                if (node == null) return;

                if (node.?.left) |left|
                    try recurse(t, left, array_list);

                try array_list.append(node.?.pieceInfo());

                if (node.?.right) |right|
                    try recurse(t, right, array_list);
            }
        };

        var array_list = try ArrayList(PieceNode.Info).initCapacity(allocator, tree.piecesCount());
        helper.recurse(tree, tree.root, &array_list) catch unreachable;
        return array_list.items;
    }

    pub fn treeFromSlice(allocator: std.mem.Allocator, infos: []const PieceNode.Info) !SplayTree {
        utils.assert(infos.len > 0, "");

        var root = try allocator.create(PieceNode);
        root.* = infos[0].toPiece();

        errdefer {
            var res_root = PieceNode.deinitTree(root, allocator);
            if (res_root) |r| allocator.destroy(r);
        }

        var size = root.len;
        var newlines_count = root.newlines_count;

        var previous_node = root;
        for (infos[1..]) |piece_info| {
            var node = try allocator.create(PieceNode);
            node.* = piece_info.toPiece();

            previous_node.right = node;
            node.parent = previous_node;

            size += piece_info.len;
            newlines_count += piece_info.newlines_count;

            previous_node = node;
        }

        return .{
            .root = root,
            .size = size,
            .newlines_count = newlines_count,
        };
    }
};

pub const PieceNode = struct {
    /// A wrapper around the same members in the PieceNode
    pub const Info = struct {
        newlines_start: u64,
        newlines_count: u64,
        start: u64,
        len: u64,
        source: Source,

        pub fn toPiece(info: Info) PieceNode {
            return .{
                .start = info.start,
                .len = info.len,
                .newlines_start = info.newlines_start,
                .newlines_count = info.newlines_count,
                .source = info.source,
            };
        }
    };

    pub const Size = struct {
        size: u64 = 0,
        newlines_count: u64 = 0,
    };

    parent: ?*PieceNode = null,
    left: ?*PieceNode = null,
    right: ?*PieceNode = null,

    left_subtree_len: u64 = 0,
    left_subtree_newlines_count: u64 = 0,

    start: u64,
    len: u64,
    newlines_start: u64,
    newlines_count: u64,
    source: Source,

    pub fn deinitTree(piece: ?*PieceNode, allocator: std.mem.Allocator) ?*PieceNode {
        if (piece == null) return null;

        var left = deinitTree(piece.?.left, allocator);
        if (left) |l| allocator.destroy(l);
        var right = deinitTree(piece.?.right, allocator);
        if (right) |r| allocator.destroy(r);

        return piece;
    }

    pub fn content(piece: *const PieceNode, pt: *const PieceTable) []const u8 {
        return switch (piece.source) {
            .original => pt.original[piece.start .. piece.start + piece.len],
            .add => pt.add.items[piece.start .. piece.start + piece.len],
        };
    }

    pub fn print(node: *PieceNode, new_line: bool) void {
        std.debug.print("s{}-{} l{} nl{} | {} {} {s}", .{
            node.start,
            node.start + node.len,
            node.len,
            node.newlines_count,
            //
            node.left_subtree_len,
            node.left_subtree_newlines_count,
            node.source.toString(),
        });

        if (new_line) std.debug.print("\n", .{});
    }

    pub fn pieceInfo(piece: PieceNode) Info {
        return .{
            .newlines_start = piece.newlines_start,
            .newlines_count = piece.newlines_count,
            .start = piece.start,
            .len = piece.len,
            .source = piece.source,
        };
    }

    pub fn toTree(node: *PieceNode) SplayTree {
        var sts = node.subtreeSize();

        return .{
            .root = node,
            .size = sts.size,
            .newlines_count = sts.newlines_count,
        };
    }

    pub fn rightSubTreeSize(node: *PieceNode, parent_left_st_size: Size) Size {
        if (node.right == null) return Size{};

        return .{
            .size = parent_left_st_size.size -| (node.len + node.left_subtree_len),
            .newlines_count = parent_left_st_size.newlines_count -| (node.newlines_count + node.left_subtree_newlines_count),
        };
    }

    pub fn subtreeSize(const_node: *PieceNode) Size {
        var subtree_size = Size{};
        var node: ?*PieceNode = const_node;
        while (node) |n| {
            subtree_size.size += n.len + n.left_subtree_len;
            subtree_size.newlines_count += n.newlines_count + n.left_subtree_newlines_count;
            node = n.right;
        }

        return subtree_size;
    }

    fn bothLeftChildOfGrandparent(node: *PieceNode, parent: *PieceNode) bool {
        return parent.left == node and parent.parent.?.left == parent;
    }

    fn bothRightChildOfGrandparent(node: *PieceNode, parent: *PieceNode) bool {
        return parent.right == node and parent.parent.?.right == parent;
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

    fn leftRotate(node: *PieceNode) void {
        utils.assert(node.parent != null, "");

        var pivot = node;
        var root = node.parent.?;

        var grand_parent = root.parent;

        var pivot_new_left_subtree_size = PieceNode.Size{
            .size = root.left_subtree_len + root.len + pivot.left_subtree_len,
            .newlines_count = root.left_subtree_newlines_count + root.newlines_count + pivot.left_subtree_newlines_count,
        };

        root.right = pivot.left;
        pivot.left = root;

        root.resetChildrenToParent();
        pivot.resetChildrenToParent();

        pivot.left_subtree_len = pivot_new_left_subtree_size.size;
        pivot.left_subtree_newlines_count = pivot_new_left_subtree_size.newlines_count;

        pivot.parent = grand_parent;
        if (grand_parent) |gp| {
            if (gp.left == root)
                gp.left = pivot
            else
                gp.right = pivot;
        }
    }

    fn rightRotate(node: *PieceNode) void {
        utils.assert(node.parent != null, "");
        var pivot = node;
        var root = node.parent.?;

        var root_new_right_subtree_size = pivot.rightSubTreeSize(.{ .size = root.left_subtree_len, .newlines_count = root.left_subtree_newlines_count });

        var grand_parent = root.parent;

        root.left = pivot.right;
        pivot.right = root;
        root.parent = pivot;

        root.resetChildrenToParent();
        pivot.resetChildrenToParent();

        root.left_subtree_len = root_new_right_subtree_size.size;
        root.left_subtree_newlines_count = root_new_right_subtree_size.newlines_count;

        pivot.parent = grand_parent;
        if (grand_parent) |gp| {
            if (gp.left == root)
                gp.left = pivot
            else
                gp.right = pivot;
        }
    }

    fn resetChildrenToParent(node: *PieceNode) void {
        if (node.left) |left| left.parent = node;
        if (node.right) |right| right.parent = node;
    }

    fn previousNode(const_node: *PieceNode) ?*PieceNode {
        if (const_node.left) |left| {
            var node = left;
            while (node.right) |right| node = right;
            return node;
        }

        return null;
    }

    fn nextNode(const_node: *PieceNode) ?*PieceNode {
        if (const_node.right) |right| {
            var node = right;
            while (node.left) |left| node = left;
            return node;
        }

        return null;
    }

    fn rootOfNode(const_node: *PieceNode) ?*PieceNode {
        var node = const_node.parent orelse return null;
        while (true) node = node.parent orelse return node;
    }

    /// Takes: the nth new line
    /// Returns: the relative index within the slice of the piece
    fn relativeNewlineIndex(piece: *PieceNode, pt: *const PieceTable, offset: u64) u64 {
        assert(piece.newlines_count > 0);
        var newlines = switch (piece.source) {
            .original => pt.original_newlines,
            .add => pt.add_newlines.items,
        };

        var index = piece.newlines_start + offset;
        if (index >= newlines.len)
            index = newlines.len -| 1;

        return newlines[index] -| piece.start;
    }

    fn newlineCountBeforeRelativeIndex(piece: *PieceNode, pt: *PieceTable, index: u64) u64 {
        var num: u64 = 0;
        while (num < piece.newlines_count) : (num += 1) {
            var relative_index = piece.relativeNewlineIndex(pt, num);
            if (relative_index >= index) break;
        }
        return num;
    }

    fn rightMostNode(const_node: *PieceNode) *PieceNode {
        var node = const_node;
        while (node.right) |right| node = right;
        return node;
    }

    fn leftMostNode(const_node: *PieceNode) *PieceNode {
        var node = const_node;
        while (node.left) |left| node = left;
        return node;
    }

    /// creates two pieces left and right where
    /// left.len = start..index
    /// right.len = index..end
    pub fn split(piece: *PieceNode, pt: *PieceTable, index: u64) struct {
        left: Info,
        right: Info,
    } {
        // assert(index <= piece.len);
        const newlines_count_for_left = piece.newlineCountBeforeRelativeIndex(pt, index);

        var left = Info{
            .newlines_start = piece.newlines_start,
            .newlines_count = newlines_count_for_left,

            .start = piece.start,
            .len = index,
            .source = piece.source,
        };

        var right = Info{
            .newlines_start = piece.newlines_start + newlines_count_for_left,
            .newlines_count = piece.newlines_count - newlines_count_for_left,

            .start = piece.start + index,
            .len = piece.len -| index,
            .source = piece.source,
        };

        return .{
            .left = left,
            .right = right,
        };
    }
};
