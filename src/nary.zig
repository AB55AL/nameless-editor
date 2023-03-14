const std = @import("std");
const ArrayList = std.ArrayList;
const utils = @import("utils.zig");

pub fn NaryTree(comptime T: type) type {
    return struct {
        const Tree = @This();

        pub const Node = struct {
            parent: ?*Node = null,
            next_sibling: ?*Node = null,
            first_child: ?*Node = null,

            data: T,

            pub fn deinitTree(node: *Node, allocator: std.mem.Allocator) void {
                if (node.first_child) |fc| fc.deinitTree(allocator);
                if (node.next_sibling) |ns| ns.deinitTree(allocator);

                allocator.destroy(node);
            }

            pub fn addAfterSibling(node: *Node, new_node: *Node) void {
                new_node.next_sibling = node.next_sibling;
                node.next_sibling = new_node;
                new_node.parent = node.parent;
            }

            pub fn appendSibling(node: *Node, new_node: *Node) void {
                var last_node = node.lastSibling();
                last_node.addAfterSibling(new_node);
            }

            pub fn prependChild(node: *Node, new_node: *Node) void {
                new_node.parent = node;
                if (node.first_child) |fc| {
                    new_node.next_sibling = fc;
                    node.first_child = new_node;
                } else {
                    node.first_child = new_node;
                }
            }

            pub fn appendChild(node: *Node, new_node: *Node) void {
                new_node.parent = node;
                if (node.first_child) |fc| {
                    fc.lastSibling().next_sibling = new_node;
                } else {
                    node.first_child = new_node;
                }
            }

            pub fn previousSibling(const_node: *Node) ?*Node {
                if (const_node.parent == null) return null;
                if (const_node == const_node.parent.?.first_child) return null;

                var node = const_node.parent.?.first_child.?;
                while (node.next_sibling) |ns| {
                    if (ns == const_node) break;
                    node = ns;
                }

                return node;
            }

            pub fn lastSibling(const_node: *Node) *Node {
                var node = const_node;
                while (true) {
                    node = node.next_sibling orelse return node;
                }
            }

            pub fn lastChild(node: *Node) ?*Node {
                return if (node.first_child) |fc| fc.lastSibling() else null;
            }

            /// Returns the ith node in the linked list of children
            pub fn getChild(node: *Node, index: u64) ?*Node {
                var child = node.first_child;
                var i: u64 = 0;
                while (child) |c| {
                    if (i == index) return c;
                    child = c.next_sibling;
                    i += 1;
                }

                return null;
            }

            pub fn treeDepth(node: *Node, level: u32) u32 {
                var res: u32 = level;
                if (node.first_child) |fc| {
                    res = fc.treeDepth(level + 1);
                }
                if (node.next_sibling) |ns| {
                    var second_res = ns.treeDepth(level);
                    if (second_res > res) res = second_res;
                }

                return res;
            }

            pub fn treeToArray(root: *Node, allocator: std.mem.Allocator) ![]*Node {
                var array_list = ArrayList(*Node).init(allocator);
                defer array_list.deinit();

                const depth = root.treeDepth(0);
                var level: u32 = 0;
                while (level <= depth) : (level += 1) {
                    try treeToArrayHelper(root, level, &array_list);
                }

                return try array_list.toOwnedSlice();
            }

            fn treeToArrayHelper(node: *Node, level: u32, array_list: *ArrayList(*Node)) std.mem.Allocator.Error!void {
                if (level == 0) {
                    var current_node: ?*Node = node;
                    while (current_node) |n| {
                        try array_list.append(n);
                        current_node = n.next_sibling;
                    }
                } else {
                    if (node.first_child) |fc| try treeToArrayHelper(fc, level - 1, array_list);
                    if (node.next_sibling) |ns| try treeToArrayHelper(ns, level, array_list);
                }
            }

            fn concat(new_parent: *Node, first_list: *Node, second_list: *Node) void {
                std.debug.assert(second_list.previousSibling() == null);

                first_list.lastSibling().next_sibling = second_list;

                var child = first_list.parent.?.first_child;
                while (child) |c| {
                    c.parent = new_parent;
                    child = c.next_sibling;
                }
            }
        };

        root: ?*Node = null,

        pub fn removePromoteLast(tree: *Tree, node: *Node) void {
            var replacment = node.lastChild();

            // Remove the node
            if (node.previousSibling()) |ps| {
                ps.next_sibling = replacment orelse node.next_sibling;
            } else if (node == tree.root) {
                tree.root = replacment;
            } else if (node.next_sibling == null and node.parent != null) {
                node.parent.?.first_child = replacment;
                if (replacment) |rep| rep.parent = node.parent;
            }

            // Promote the replacement
            if (replacment) |rep| {
                if (rep.previousSibling()) |ps| {
                    ps.next_sibling = null;
                    if (rep.first_child) |fc|
                        Node.concat(rep, ps, fc);

                    rep.first_child = node.first_child;
                }
            }
        }

        pub fn deinitTree(tree: *Tree, allocator: std.mem.Allocator) void {
            if (tree.root) |root| root.deinitTree(allocator);
        }
    };
}

test "nary" {
    const allocator = std.testing.allocator;

    const Node = NaryTree(u32).Node;
    var tree = NaryTree(u32){};
    defer tree.deinitTree(allocator);

    // zig fmt: off
    // depth 0
    var n0 = try allocator.create(Node); n0.* = .{ .data = 0 };

    // depth 1
    var n1 = try allocator.create(Node); n1.* = .{ .data = 0 };
    var n2 = try allocator.create(Node); n2.* = .{ .data = 0 };
    var n3 = try allocator.create(Node); n3.* = .{ .data = 0 };

    // depth 2
    var n1_0 = try allocator.create(Node); n1_0.* = .{ .data = 0 };

    var n2_0 = try allocator.create(Node); n2_0.* = .{.data = 0};
    var n2_1 = try allocator.create(Node); n2_1.* = .{.data = 0};

    var n3_0 = try allocator.create(Node); n3_0.* = .{.data = 0};
    var n3_1 = try allocator.create(Node); n3_1.* = .{.data = 0};
    var n3_2 = try allocator.create(Node); n3_2.* = .{.data = 0};

    // depth 3
    var n1_1_0 = try allocator.create(Node); n1_1_0.* = .{ .data = 0 };
    // zig fmt: on

    tree.root = n0;

    n0.appendChild(n1);
    n1.addAfterSibling(n2);
    n2.addAfterSibling(n3);

    n1.appendChild(n1_0);
    n1_0.appendChild(n1_1_0);

    n2.appendChild(n2_0);
    n2_0.addAfterSibling(n2_1);

    n3.appendChild(n3_0);
    n3_0.addAfterSibling(n3_1);
    n3_1.addAfterSibling(n3_2);

    var nodes = try tree.root.?.treeToArray(allocator);
    defer allocator.free(nodes);

    tree.removePromoteLast(n3_1);
    allocator.destroy(n3_1);

    var root = tree.root.?;
    try std.testing.expectEqual(root, n0);

    try std.testing.expectEqual(root.getChild(0), n1);
    try std.testing.expectEqual(root.getChild(1), n2);
    try std.testing.expectEqual(root.getChild(2), n3);
    try std.testing.expectEqual(root.getChild(3), null);

    try std.testing.expectEqual(n1.getChild(0), n1_0);
    try std.testing.expectEqual(n1.getChild(1), null);

    try std.testing.expectEqual(n2.getChild(0), n2_0);
    try std.testing.expectEqual(n2.getChild(1), n2_1);
    try std.testing.expectEqual(n2.getChild(2), null);

    try std.testing.expectEqual(n3.getChild(0), n3_0);
    try std.testing.expectEqual(n3.getChild(1), n3_2);
    try std.testing.expectEqual(n3.getChild(2), null);

    tree.removePromoteLast(root);
    allocator.destroy(root);

    try std.testing.expectEqual(tree.root.?, n3);

    tree.removePromoteLast(n1_0);
    allocator.destroy(n1_0);

    try std.testing.expectEqual(n1.getChild(0), n1_1_0);

    tree.removePromoteLast(n1_1_0);
    allocator.destroy(n1_1_0);
}
