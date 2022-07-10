const std = @import("std");
const expect = std.testing.expect;
const allocator = std.testing.allocator;

const core = @import("core");
const Buffer = core.Buffer;
const history = core.history;

test "undo and redo deleteRange()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
    ;

    const string_after_change =
        \\hello there my friend
        \\tدهش Amazing isn't it ?!
    ;

    var buffer = try Buffer.init(allocator, "", original_text);
    defer buffer.deinit();

    try buffer.deleteRange(2, 2, 3, 22);

    var content = try buffer.copyAll();
    try expect(std.mem.eql(u8, content, string_after_change));

    try history.undo(buffer);
    var after_undo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_undo, original_text));

    try history.redo(buffer);
    var after_redo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_redo, string_after_change));

    try history.undo(buffer);
    var after_another_undo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_another_undo, original_text));

    try history.redo(buffer);
    var after_another_redo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_another_redo, string_after_change));

    allocator.free(content);
    allocator.free(after_undo);
    allocator.free(after_redo);
    allocator.free(after_another_undo);
    allocator.free(after_another_redo);
}

test "undo and rode delete()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const string_after_change =
        \\hello there my friend
        \\with three lines!!!!
    ;

    var buffer = try Buffer.init(allocator, "", original_text);
    defer buffer.deinit();

    try buffer.delete(2, 1, 999);
    var content = try buffer.copyAll();
    try expect(std.mem.eql(u8, content, string_after_change));

    try history.undo(buffer);
    var after_undo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_undo, original_text));

    try history.redo(buffer);
    var after_redo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_redo, string_after_change));

    try history.undo(buffer);
    var after_another_undo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_another_undo, original_text));

    try history.redo(buffer);
    var after_another_redo = try buffer.copyAll();
    try expect(std.mem.eql(u8, after_another_redo, string_after_change));

    allocator.free(content);
    allocator.free(after_undo);
    allocator.free(after_redo);
    allocator.free(after_another_undo);
    allocator.free(after_another_redo);
}

test "test the three cases of delete()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const deleted_whole_line =
        \\hello there my friend
        \\with three lines!!!!
    ;

    const deleted_within_line =
        \\hello friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const deleted_new_line =
        \\hellothis is a test text.
        \\with three lines!!!!
    ;

    var buffer_1 = try Buffer.init(allocator, "", original_text);
    var buffer_2 = try Buffer.init(allocator, "", original_text);
    var buffer_3 = try Buffer.init(allocator, "", original_text);

    try buffer_1.delete(2, 1, 999);
    var content_1 = try buffer_1.copyAll();
    try expect(std.mem.eql(u8, content_1, deleted_whole_line));

    try buffer_2.delete(1, 7, 16);
    var content_2 = try buffer_2.copyAll();
    try expect(std.mem.eql(u8, content_2, deleted_within_line));

    try buffer_3.delete(1, 6, 999);
    var content_3 = try buffer_3.copyAll();
    try expect(std.mem.eql(u8, content_3, deleted_new_line));

    allocator.free(content_1);
    allocator.free(content_2);
    allocator.free(content_3);
    buffer_1.deinit();
    buffer_2.deinit();
    buffer_3.deinit();
}

test "test the two cases of insert()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const added_text_with_no_newline =
        \\hello _ADDED TEXT HERE_ there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const added_text_with_newline =
        \\hello there my friend
        \\this is a MODIFIED
        \\test text.
        \\with three lines!!!!
    ;

    var buffer_1 = try Buffer.init(allocator, "", original_text);
    var buffer_2 = try Buffer.init(allocator, "", original_text);

    try buffer_1.insert(1, 6, " _ADDED TEXT HERE_");
    var content_1 = try buffer_1.copyAll();
    try expect(std.mem.eql(u8, content_1, added_text_with_no_newline));

    try buffer_2.insert(2, 11, "MODIFIED\n");
    var content_2 = try buffer_2.copyAll();
    try expect(std.mem.eql(u8, content_2, added_text_with_newline));

    allocator.free(content_1);
    allocator.free(content_2);
    buffer_1.deinit();
    buffer_2.deinit();
}

test "test the two cases of insert() + undo and redo" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const added_text_with_no_newline =
        \\hello _ADDED TEXT HERE_ there my friend
        \\this is a test text.
        \\with three lines!!!!
    ;

    const added_text_with_newline =
        \\hello there my friend
        \\this is a MODIFIED
        \\TEXT
        \\OVER
        \\HERE
        \\test text.
        \\with three lines!!!!
    ;

    ////////////////////////////////////////////////////////////////
    // no new line

    var buffer_no_newline = try Buffer.init(allocator, "", original_text);
    var buffer_newline = try Buffer.init(allocator, "", original_text);

    try buffer_no_newline.insert(1, 6, " _ADDED TEXT HERE_");
    var content_1 = try buffer_no_newline.copyAll();
    try expect(std.mem.eql(u8, content_1, added_text_with_no_newline));

    try history.updateHistory(buffer_no_newline);

    try history.undo(buffer_no_newline);
    var after_undo = try buffer_no_newline.copyAll();
    try expect(std.mem.eql(u8, after_undo, original_text));

    try history.redo(buffer_no_newline);
    var after_redo = try buffer_no_newline.copyAll();
    try expect(std.mem.eql(u8, after_redo, added_text_with_no_newline));

    ////////////////////////////////////////////////////////////////
    // with new line

    try buffer_newline.insert(2, 11, "MODIFIED\nTEXT\nOVER\nHERE\n");
    var content_2 = try buffer_newline.copyAll();
    try expect(std.mem.eql(u8, content_2, added_text_with_newline));

    try history.updateHistory(buffer_newline);

    try history.undo(buffer_newline);
    var newline_after_undo = try buffer_newline.copyAll();
    try expect(std.mem.eql(u8, newline_after_undo, original_text));

    try history.redo(buffer_newline);
    var newline_after_redo = try buffer_newline.copyAll();

    try expect(std.mem.eql(u8, newline_after_redo, added_text_with_newline));
    ////////////////////////////////////////////////////////////////

    allocator.free(content_1);
    allocator.free(after_undo);
    allocator.free(after_redo);

    allocator.free(content_2);
    allocator.free(newline_after_undo);
    allocator.free(newline_after_redo);

    buffer_no_newline.deinit();
    buffer_newline.deinit();
}
