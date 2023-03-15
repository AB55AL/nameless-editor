const std = @import("std");
const expect = std.testing.expect;
const allocator = std.testing.allocator;
const print = std.debug.print;
const expectEqualStrings = std.testing.expectEqualStrings;
const ArrayList = std.ArrayList;

const core = @import("core");
const Buffer = core.Buffer;

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

    var buffer = try Buffer.init(allocator, "", original_text);
    defer buffer.deinitNoDestroy();

    try buffer.deleteRange(2, 2, 3, 22);

    const buffer_slice = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_slice);
    try expectEqualStrings(string_after_change, buffer_slice);
}

test "deleteRows()" {
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

    var buffer = try Buffer.init(allocator, "", original_text);
    defer buffer.deinitNoDestroy();

    {
        try buffer.deleteRows(1, 5);
        const buffer_slice = try buffer.getAllLines(allocator);
        defer allocator.free(buffer_slice);
        try std.testing.expectEqualStrings(begin_to_end, buffer_slice);
    }

    try buffer.replaceAllWith(original_text);
    {
        try buffer.deleteRows(1, 3);
        const buffer_slice = try buffer.getAllLines(allocator);
        defer allocator.free(buffer_slice);
        try std.testing.expectEqualStrings(begin_to_mid, buffer_slice);
    }

    try buffer.replaceAllWith(original_text);
    {
        try buffer.deleteRows(2, 4);
        const buffer_slice = try buffer.getAllLines(allocator);
        defer allocator.free(buffer_slice);
        try std.testing.expectEqualStrings(mid_to_mid, buffer_slice);
    }

    try buffer.replaceAllWith(original_text);
    {
        try buffer.deleteRows(2, 5);
        const buffer_slice = try buffer.getAllLines(allocator);
        defer allocator.free(buffer_slice);
        try std.testing.expectEqualStrings(mid_to_end, buffer_slice);
    }

    try buffer.replaceAllWith(original_text);
    {
        try buffer.deleteRows(1, 1);
        const buffer_slice = try buffer.getAllLines(allocator);
        defer allocator.free(buffer_slice);
        try std.testing.expectEqualStrings(same_line, buffer_slice);
    }
}

test "buffer.insertBeforeCursor()" {
    const string =
        \\HELLO THERE! GENERAL
        \\KENOBI
        \\
    ;

    var buffer = try Buffer.init(allocator, "", "HELLO THERE\n");
    defer buffer.deinitNoDestroy();

    buffer.cursor_index = 11;
    try buffer.insertBeforeCursor("! GENERAL");
    buffer.cursor_index = 21;
    try buffer.insertBeforeCursor("KENOBI\n");

    const buffer_slice = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_slice);
    try expectEqualStrings(string, buffer_slice);
}

test "buffer.getAllLines()" {
    const this_file = @embedFile("buffer.zig");
    var buffer = try Buffer.init(allocator, "", this_file);
    defer buffer.deinitNoDestroy();

    const buffer_slice = try buffer.getAllLines(allocator);
    defer allocator.free(buffer_slice);
    try expectEqualStrings(this_file, buffer_slice);
}

test "History" {
    //              hello
    //             /     \
    //          yes       EMPTY

    var buffer = try Buffer.init(allocator, "", "hello");
    defer buffer.deinitNoDestroy();

    var old_tree_content = try buffer.getAllLines(allocator);
    defer allocator.free(old_tree_content);

    try buffer.clear();
    var new_tree_content = try buffer.getAllLines(allocator);
    defer allocator.free(new_tree_content);

    try buffer.undo();
    var old_tree_again = try buffer.getAllLines(allocator);
    defer allocator.free(old_tree_again);

    try expectEqualStrings(old_tree_content, old_tree_again);

    try buffer.replaceAllWith("yes");
    var yes = try buffer.getAllLines(allocator);
    defer allocator.free(yes);

    try buffer.pushHistory(true);
    try buffer.undo();

    try buffer.redo(0);
    var new_tree_again = try buffer.getAllLines(allocator);
    defer allocator.free(new_tree_again);

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
