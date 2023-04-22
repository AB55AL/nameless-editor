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

            pub const freeDataFn = fn (allocator: std.mem.Allocator, data: *T) void;
            pub const Data = T;

            pub fn deinitTree(node: *Node, allocator: std.mem.Allocator, comptime freeData: ?freeDataFn) void {
                if (node.first_child) |fc| fc.deinitTree(allocator, freeData);
                if (node.next_sibling) |ns| ns.deinitTree(allocator, freeData);

                if (freeData) |free|
                    free(allocator, &node.data);
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

            pub fn prependListAsChildren(node: *Node, new_list_head: *Node) void {
                var current_node = new_list_head;
                while (true) {
                    current_node.parent = node;
                    current_node = current_node.next_sibling orelse break;
                }

                if (node.first_child) |fc|
                    current_node.next_sibling = fc;

                node.first_child = new_list_head;
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

                var node = const_node.parent.?.first_child;
                while (node) |n| {
                    if (n.next_sibling == const_node) break;
                    node = n.next_sibling;
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

            pub fn remove(node: *Node) void {
                var parent = node.parent orelse return; // node is root
                if (parent.first_child == node) {
                    parent.first_child = node.next_sibling;
                } else {
                    var current_node = parent.first_child.?;
                    while (current_node.next_sibling != node) {
                        current_node = current_node.next_sibling.?;
                    }
                    current_node.next_sibling = node.next_sibling;
                }

                node.parent = null;
                node.next_sibling = null;
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

            fn concat(new_parent: *Node, first_list_head: *Node, second_list_head: *Node) void {
                std.debug.assert(second_list_head.previousSibling() == null);
                std.debug.assert(first_list_head.previousSibling() == null);

                first_list_head.lastSibling().next_sibling = second_list_head;

                var child: ?*Node = first_list_head;
                while (child) |c| {
                    c.parent = new_parent;
                    child = c.next_sibling;
                }

                new_parent.first_child = first_list_head;
            }
        };

        root: ?*Node = null,

        pub fn removePromoteLast(tree: *Tree, node: *Node) void {
            // Remove the replacement
            // Remove the Node
            // Insert replacement after node.previous_sibling
            //        OR for root node set replacement as root
            // Concat node and replacement subtrees

            var node_previous_sibling = node.previousSibling();
            var node_parent = node.parent;
            var replacment = node.lastChild();
            if (replacment) |rep| rep.remove();
            node.remove();

            var node_list_of_subtrees = node.first_child;
            var rep_list_of_subtrees = if (replacment) |rep| rep.first_child else null;

            if (replacment) |rep| {
                if (node == tree.root)
                    tree.root = rep
                else if (node_previous_sibling) |nps|
                    nps.addAfterSibling(rep)
                else
                    node_parent.?.prependChild(rep);

                if (node_list_of_subtrees != null and rep_list_of_subtrees != null)
                    Node.concat(rep, node_list_of_subtrees.?, rep_list_of_subtrees.?)
                else if (node_list_of_subtrees) |ns|
                    rep.prependListAsChildren(ns)
                else if (rep_list_of_subtrees) |rs|
                    rep.prependListAsChildren(rs);
            } else if (node == tree.root) {
                tree.root = null;
            }
        }

        pub fn deinitTree(tree: *Tree, allocator: std.mem.Allocator, comptime freeData: ?Node.freeDataFn) void {
            if (tree.root) |root| root.deinitTree(allocator, freeData);
            tree.root = null;
        }

        pub fn treeToArray(tree: *Tree, allocator: std.mem.Allocator) ![]*Node {
            const Contex = struct {
                array_list: *ArrayList(*Node),

                pub fn do(self: *@This(), node: *Node) bool {
                    self.array_list.append(node) catch {
                        self.array_list.clearAndFree();
                        return false;
                    };

                    return true;
                }
            };

            var array_list = ArrayList(*Node).init(allocator);
            defer array_list.deinit();
            var ctx = Contex{ .array_list = &array_list };
            tree.levelOrderTraverse(&ctx);

            return try array_list.toOwnedSlice();
        }

        pub fn levelOrderTraverse(tree: *Tree, context: anytype) void {
            const traverse = struct {
                fn recurse(node: *Node, current_level: u64, ctx: anytype) bool {
                    if (current_level == 0) {
                        var current_node: ?*Node = node;
                        while (current_node) |n| {
                            if (!ctx.do(n)) return false;
                            current_node = n.next_sibling;
                        }
                    } else {
                        if (node.first_child) |fc| return recurse(fc, current_level - 1, ctx);
                        if (node.next_sibling) |ns| return recurse(ns, current_level, ctx);
                    }

                    return true;
                }
            }.recurse;

            var root = tree.root orelse return;
            const depth = root.treeDepth(0);
            for (0..depth + 1) |level|
                if (!traverse(root, level, context)) break;
        }
    };
}

test "nary" {
    const allocator = std.testing.allocator;

    const Node = NaryTree(u32).Node;
    var tree = NaryTree(u32){};
    defer tree.deinitTree(allocator, null);

    // zig fmt: off
    // depth 0
    var n0 = try allocator.create(Node); n0.* = .{ .data = 0 };

    // depth 1
    var n1 = try allocator.create(Node); n1.* = .{ .data = 1 };
    var n2 = try allocator.create(Node); n2.* = .{ .data = 2 };
    var n3 = try allocator.create(Node); n3.* = .{ .data = 3 };

    // depth 2
    var n1_0 = try allocator.create(Node); n1_0.* = .{ .data = 10 };

    var n2_0 = try allocator.create(Node); n2_0.* = .{.data = 20};
    var n2_1 = try allocator.create(Node); n2_1.* = .{.data = 21};

    var n3_0 = try allocator.create(Node); n3_0.* = .{.data = 30};
    var n3_1 = try allocator.create(Node); n3_1.* = .{.data = 31};
    var n3_2 = try allocator.create(Node); n3_2.* = .{.data = 32};

    // depth 3
    var n1_1_0 = try allocator.create(Node); n1_1_0.* = .{ .data = 110 };
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

    var nodes = try tree.treeToArray(allocator);
    defer allocator.free(nodes);

    tree.removePromoteLast(n3_1);
    allocator.destroy(n3_1);

    tree.removePromoteLast(n2);
    allocator.destroy(n2);

    var root = tree.root.?;
    try std.testing.expectEqual(root, n0);

    try std.testing.expectEqual(root.getChild(0), n1);
    try std.testing.expectEqual(root.getChild(1), n2_1);
    try std.testing.expectEqual(root.getChild(2), n3);
    try std.testing.expectEqual(root.getChild(3), null);

    try std.testing.expectEqual(n1.getChild(0), n1_0);
    try std.testing.expectEqual(n1.getChild(1), null);

    try std.testing.expectEqual(n2_1.getChild(0), n2_0);

    try std.testing.expectEqual(n3.getChild(0), n3_0);
    try std.testing.expectEqual(n3.getChild(1), n3_2);
    try std.testing.expectEqual(n3.getChild(2), null);

    tree.removePromoteLast(root);
    allocator.destroy(root);

    root = tree.root.?;
    try std.testing.expectEqual(root, n3);
    try std.testing.expectEqual(root.getChild(0), n1);
    try std.testing.expectEqual(root.getChild(1), n2_1);
    try std.testing.expectEqual(root.getChild(2), n3_0);
    try std.testing.expectEqual(root.getChild(3), n3_2);
    try std.testing.expectEqual(root.getChild(4), null);

    tree.removePromoteLast(n1_0);
    allocator.destroy(n1_0);

    try std.testing.expectEqual(n1.getChild(0), n1_1_0);

    tree.removePromoteLast(n1_1_0);
    allocator.destroy(n1_1_0);
}
