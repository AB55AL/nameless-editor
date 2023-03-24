const std = @import("std");
const unicode = std.unicode;
const expect = std.testing.expect;
const print = std.debug.print;
const expectEqualStrings = std.testing.expectEqualStrings;
const ArrayList = std.ArrayList;
const fs = std.fs;
const random = std.crypto.random;

const test_allocator = std.testing.allocator;

const core = @import("core");
const Buffer = core.Buffer;

const Mod = struct {
    const Operation = union(enum) {
        deletion_end_index: u64,
        insertion_string: []const u8,

        fn toString(op: Operation) []const u8 {
            return switch (op) {
                .insertion_string => "INS",
                .deletion_end_index => "DEL",
            };
        }
    };

    // type: enum { insertion, deletion },
    index: u64,
    // end_index: u64, // only matters for deletion
    // string: []const u8, // only matters for insertion

    operation: Operation,

    fn applyToBuffer(mod: Mod, buffer: *Buffer, allocator: std.mem.Allocator) !void {
        switch (mod.operation) {
            .insertion_string => |string| {
                try buffer.insertAt(mod.index, string);
            },
            .deletion_end_index => |end_index| {
                buffer.deleteRange(mod.index, end_index) catch |err| {
                    std.debug.print("{!} {}, {}\n", .{ err, mod.index, end_index });
                    const buffer_slice = try buffer.getAllLines(allocator);
                    defer allocator.free(buffer_slice);
                    for (buffer_slice, 0..) |byte, i|
                        std.debug.print("{} {} {}\n", .{ i, core.utf8.byteType(byte), byte });

                    return err;
                };
            },
        }
    }

    fn applyToArrayList(mod: Mod, array_list: *ArrayList(u8)) !void {
        switch (mod.operation) {
            .insertion_string => |string| try array_list.insertSlice(mod.index, string),
            .deletion_end_index => |end_index| {
                var count = mod.index;
                while (count <= end_index) {
                    _ = array_list.orderedRemove(mod.index);
                    count += 1;
                }
            },
        }

        var last = array_list.getLastOrNull();
        if (last == null or last.? != '\n')
            try array_list.append('\n');
    }

    fn deinit(buffer: *Buffer, array_list: *ArrayList(u8), mods: *ArrayList(Mod), allocator: std.mem.Allocator) void {
        buffer.deinitNoDestroy();

        for (mods.items) |item|
            if (item.operation == .insertion_string)
                allocator.free(item.operation.insertion_string);

        array_list.deinit();
        mods.deinit();
    }
};

fn fuzzEqlTest(buffer: *Buffer, buffer_array: *ArrayList(u8), allocator: std.mem.Allocator) !void {
    const buffer_content = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_content);

    if (!unicode.utf8ValidateSlice(buffer_content)) return error.InvalidUTF8;
    try expectEqualStrings(buffer_array.items, buffer_content);
}

fn bufferEql(expected: []const u8, buffer: *Buffer) !void {
    var buffer_content = try buffer.getAllLines(buffer.allocator);
    defer buffer.allocator.free(buffer_content);

    try expectEqualStrings(expected, buffer_content);
}

fn randomCodePoint() u21 {
    // small chance of a newline character
    if (random.int(u8) == 0) return '\n';

    while (true) {
        var cp = random.intRangeAtMost(u21, 1, comptime std.math.maxInt(u16));
        if (unicode.utf8ValidCodepoint(cp)) return cp;
        // std.debug.print("randomCodePoint()\n", .{});
    }
}

fn randomUTF8String(size: u64, allocator: std.mem.Allocator) []const u8 {
    var buf = allocator.alloc(u8, size) catch unreachable;

    var i: u64 = 0;
    while (i < buf.len) {
        var string: [4]u8 = undefined;
        var bytes = unicode.utf8Encode(randomCodePoint(), &string) catch unreachable;
        if (i + bytes > buf.len) {
            // std.debug.print("randomUTF8String()\n", .{});
            continue;
        }

        std.mem.copy(u8, buf[i..], string[0..bytes]);
        i += bytes;
    }

    return buf;
}

fn randomVaildIndex(buffer: *Buffer) u64 {
    var row = random.intRangeAtMost(u64, 1, buffer.lineCount());
    var col = random.intRangeAtMost(u64, 1, buffer.countCodePointsAtRow(row));
    var index = buffer.getIndex(row, col);
    return index;
}

fn generateMod(buffer: *Buffer, string_len: u64, allocator: std.mem.Allocator) Mod {
    var index = randomVaildIndex(buffer);

    var operation = blk: {
        const insert = random.int(u32) % 2 == 0;

        if (insert) {
            break :blk Mod.Operation{ .insertion_string = randomUTF8String(string_len, allocator) };
        } else {
            var end_index = randomVaildIndex(buffer);
            while (end_index < index) end_index = randomVaildIndex(buffer);
            end_index += (unicode.utf8ByteSequenceLength(buffer.lines.byteAt(end_index)) catch unreachable) - 1;

            break :blk Mod.Operation{ .deletion_end_index = end_index };
        }
    };

    return .{
        .index = index,
        .operation = operation,
    };
}

fn printContent(array_list: ArrayList(u8), buffer: *Buffer, allocator: std.mem.Allocator) !void {
    const buffer_slice = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_slice);
    std.debug.print("BUF {any}\n", .{buffer_slice});
    std.debug.print("ARR {any}\n", .{array_list.items});
}

fn validateUTF8(buffer: *Buffer, allocator: std.mem.Allocator) !void {
    const buffer_slice = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_slice);
    if (!unicode.utf8ValidateSlice(buffer_slice)) return error.InvalidUTF8;
}

fn printTree(buffer: *Buffer, allocator: std.mem.Allocator) void {
    var pt = &buffer.lines;
    var tree = &buffer.lines.tree;
    // buffer.lines.tree.printTree(buffer.allocator) catch unreachable;
    // _ = buffer.lines.tree.root.?.toString() catch unreachable;
    // var depth = buffer.lines.tree.treeDepth();
    // std.debug.print("DEPTH = {}\n", .{depth});

    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines);

    tree.printTreeOrdered(pt, allocator) catch unreachable;
}

fn modSlice() []const Mod {
    const b = @This();
    const tests = struct {
        pub const buffer = b;
    };
    return &[_]Mod{
        tests.buffer.Mod{ .index = 0, .operation = tests.buffer.Mod.Operation{ .insertion_string = &.{ 236, 147, 128, 233, 143, 139, 225, 132, 141, 10 } } },
        tests.buffer.Mod{ .index = 6, .operation = tests.buffer.Mod.Operation{ .deletion_end_index = 9 } },
        tests.buffer.Mod{ .index = 3, .operation = tests.buffer.Mod.Operation{ .insertion_string = &.{ 238, 181, 132, 229, 128, 177, 229, 182, 152, 124 } } },
        tests.buffer.Mod{ .index = 12, .operation = tests.buffer.Mod.Operation{ .deletion_end_index = 12 } },
        tests.buffer.Mod{ .index = 12, .operation = tests.buffer.Mod.Operation{ .deletion_end_index = 15 } },
    };
}

//  236, 147, 128, 238, 181, 132, 229, 128, 177, 229, 182, 152, 233, 143, 139, 10
//  236, 147, 128, 238, 181, 132, 229, 128, 177, 229, 182, 152
// insureLastByteIsNewLine()
//  236, 147, 128, 238, 181, 132, 229, 128, 177, 229, 182, 152, 10

// test "fuzz modify the buffer non-random" {
//     std.debug.print("\n", .{});

//     var mods = comptime modSlice();

//     var buffer = try Buffer.init(allocator, "", "");
//     defer buffer.deinitNoDestroy();

//     var buffer_array = ArrayList(u8).init(allocator);
//     try buffer_array.append('\n');
//     defer buffer_array.deinit();

//     for (mods) |mod|
//         std.debug.print("{}\n", .{mod});

//     std.debug.print("________________________________________\n", .{});

//     for (mods, 0..) |mod, mod_index| {
//         std.debug.print("MOD_INDEX = {} {s}\n", .{ mod_index, mod.operation.toString() });

//         var target_index: u64 = 4;
//         if (mod_index == target_index) {
//             std.debug.print("======================================\n", .{});
//             std.debug.print("BEFORE\n", .{});
//             printTree(&buffer);
//             try printContent(buffer_array, &buffer);
//         }

//         try mod.applyToBuffer(&buffer);
//         try mod.applyToArrayList(&buffer_array);

//         if (mod_index == target_index) {
//             std.debug.print("AFTER\n", .{});
//             printTree(&buffer);
//             try printContent(buffer_array, &buffer);
//         }
//         try fuzzEqlTest(&buffer, &buffer_array);
//     }

//     std.debug.print("----------------------------------------\n", .{});
//     std.debug.print("{s:^40}\n", .{"END OF MANUAL FUZZ TEST"});
//     std.debug.print("----------------------------------------\n", .{});
// }

test "fuzz modify the buffer" {
    std.debug.print("\n", .{});
    var timer = try std.time.Timer.start();
    defer std.debug.print("time {}\n", .{timer.read() / std.time.ns_per_ms});

    const randomize = true;
    const buffer_test_count = 10;
    const mod_count = if (randomize) std.crypto.random.intRangeAtMost(u64, 500, 1000) else 500;

    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    for (0..buffer_test_count) |btc| {
        if (gpa.detectLeaks()) return error.MemoryLeak;

        if (btc % 10 == 0) {
            std.debug.print("----------------------------------------\n", .{});
            std.debug.print("{s:^40}\n{:^40}\n", .{ "START OF NEW BUFFER MOD", btc });
            std.debug.print("----------------------------------------\n", .{});
        }

        const string_len = if (randomize) std.crypto.random.intRangeAtMost(u64, 1, 1000) else 500;

        var mods = ArrayList(Mod).init(allocator);
        var buffer = try Buffer.init(allocator, "", "");
        var buffer_array = ArrayList(u8).init(allocator);
        try buffer_array.append('\n'); // emulate Buffer.insureLastByteIsNewLine()

        defer Mod.deinit(&buffer, &buffer_array, &mods, allocator);

        for (0..mod_count) |_| {
            var mod = generateMod(&buffer, string_len, allocator);
            try mods.append(mod);

            try mod.applyToBuffer(&buffer, allocator);
            try mod.applyToArrayList(&buffer_array);

            try fuzzEqlTest(&buffer, &buffer_array, allocator);
        }
    }

    // std.debug.print("{s}", .{buffer_slice});

    // const file_path = "~/TEST-DATA";
    // var file_dir = try fs.openDirAbsolute(fs.path.dirname(file_path).?, .{});
    // defer file_dir.close();
    // var file = try file_dir.openFile(file_path, .{ .mode = .write_only });
    // defer file.close();
    // try file.writeAll(buffer_slice);
}

test "deleteRange()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
        \\
    ; // the editor always insures a newline at is the end

    const string_after_change =
        \\hello there my friend
        \\tدهش Amazing isn't it ?!
        \\
    ;

    var buffer = try Buffer.init(test_allocator, "", original_text);
    defer buffer.deinitNoDestroy();

    std.debug.assert(buffer.lines.tree.root.?.left == null);
    std.debug.assert(buffer.lines.tree.root.?.right == null);
    std.debug.assert(buffer.lines.tree.root.?.parent == null);
    std.debug.assert(buffer.lines.tree.root.?.source == .original);

    try buffer.deleteRangeRC(2, 2, 3, 22);

    const buffer_slice = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(buffer_slice);
    try expectEqualStrings(string_after_change, buffer_slice);
}

test "deleteRows()" {
    // std.debug.print("===========================================\n", .{});
    // std.debug.print("===========================================\n", .{});
    // std.debug.print("===========================================\n", .{});

    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ; // the editor always insures a newline at is the end

    const begin_to_end = "\n"; // the editor always insures a newline at is the end

    const begin_to_mid =
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ;
    const mid_to_mid =
        \\hello there my friend
        \\And heres some more
        \\
    ;
    const mid_to_end =
        \\hello there my friend
        \\
    ;

    const same_line =
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ;

    var buffer = try Buffer.init(test_allocator, "", original_text);
    defer buffer.deinitNoDestroy();

    try buffer.deleteRows(1, 5);
    try bufferEql(begin_to_end, &buffer);

    try buffer.replaceAllWith(original_text);
    try buffer.deleteRows(1, 3);
    try bufferEql(begin_to_mid, &buffer);

    try buffer.replaceAllWith(original_text);
    try buffer.deleteRows(2, 4);
    try bufferEql(mid_to_mid, &buffer);

    try buffer.replaceAllWith(original_text);
    try buffer.deleteRows(2, 5);
    try bufferEql(mid_to_end, &buffer);

    try buffer.replaceAllWith(original_text);
    try buffer.deleteRows(1, 1);
    try bufferEql(same_line, &buffer);
}

test "buffer.insertBeforeCursor()" {
    // std.debug.print("==========================\n", .{});
    const string =
        \\HELLO THERE! GENERAL
        \\KENOBI
        \\
    ;

    var buffer = try Buffer.init(test_allocator, "", "HELLO THERE\n");
    defer buffer.deinitNoDestroy();

    buffer.cursor_index = 11;
    try buffer.insertBeforeCursor("! GENERAL");

    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);

    try bufferEql(string[0..21], &buffer);

    buffer.cursor_index = 21;
    try buffer.insertBeforeCursor("KENOBI\n");

    const buffer_slice = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(buffer_slice);
    try expectEqualStrings(string, buffer_slice);
}

test "buffer.getAllLines()" {
    const this_file = @embedFile("buffer.zig");
    var buffer = try Buffer.init(test_allocator, "", this_file);
    defer buffer.deinitNoDestroy();

    const buffer_slice = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(buffer_slice);
    try expectEqualStrings(this_file, buffer_slice);
}

test "buffer" {
    var buffer = try Buffer.init(test_allocator, "", "hello\nthere\n");
    defer buffer.deinitNoDestroy();
    // std.debug.print("DONE DEINITG\n", .{});

    buffer.cursor_index = 5;
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    try buffer.insertBeforeCursor("i"); // (hello) (i) (\nthere\n)

    // std.debug.print("AFTER i INSERT\n", .{});
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    try buffer.deleteBeforeCursor(1); // (hello) (\nthere\n)
    // std.debug.print("AFTER i delete\n", .{});
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    // std.debug.print("==\n", .{});
    try buffer.insertBeforeCursor(" "); // (hello) ( ) (\nthere\n)
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);

    try bufferEql("hello \nthere\n", &buffer);
}

test "utf8 delete" {
    const original_text = "نعم إنه مدهش Amazing isn't it ?!\n";
    const target_text = "نه مدهش Amazing isn't it ?!\n";
    var buffer = try Buffer.init(test_allocator, "", original_text);
    defer buffer.deinitNoDestroy();

    try buffer.deleteRange(0, 8);
    try bufferEql(target_text, &buffer);
}

test "History" {
    //              hello\n
    //             /     \
    //          yes\n       \n

    var buffer = try Buffer.init(test_allocator, "", "hello");
    defer buffer.deinitNoDestroy();

    var old_tree_content = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(old_tree_content);

    try buffer.clear();
    var new_tree_content = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(new_tree_content);

    try buffer.undo();
    var old_tree_again = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(old_tree_again);

    try expectEqualStrings(old_tree_content, old_tree_again);

    // std.debug.print("ABOUT TO DO YES\n", .{});
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    try buffer.replaceAllWith("yes");
    // std.debug.print("DONE WITH YES\n", .{});
    // buffer.lines.tree.printTreeTraverseTrace(&buffer.lines, buffer.lines.tree.root);
    var yes = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(yes);

    try buffer.pushHistory(true);
    try buffer.undo();

    try buffer.redo(0);
    var new_tree_again = try buffer.getAllLines(test_allocator);
    defer test_allocator.free(new_tree_again);

    try expectEqualStrings(new_tree_content, new_tree_again);

    try buffer.undo();
    try expectEqualStrings(old_tree_content, old_tree_again);

    try buffer.redo(1);
    try expectEqualStrings("yes\n", yes);

    try buffer.redo(0);
    try buffer.redo(0);
    try buffer.redo(0);
    try buffer.redo(0);

    try buffer.undo();
    try buffer.undo();
    try buffer.undo();
    try buffer.undo();
    try buffer.undo();
}
