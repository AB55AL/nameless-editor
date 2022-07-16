const std = @import("std");
const expect = std.testing.expect;
const allocator = std.testing.allocator;
const print = std.debug.print;
const expectEqualStrings = std.testing.expectEqualStrings;

const core = @import("core");
const Buffer = core.Buffer;
const history = core.history;

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
    defer buffer.deinit();

    try buffer.deleteRange(2, 2, 3, 22);
    try std.testing.expectEqualStrings(string_after_change, buffer.lines.sliceOfContent());
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
    var lines = &buffer.lines;
    defer buffer.deinit();

    try buffer.deleteRows(1, 5);
    try std.testing.expectEqualStrings(begin_to_end, lines.sliceOfContent());

    try lines.replaceAllWith(original_text);
    try buffer.deleteRows(1, 3);
    try std.testing.expectEqualStrings(begin_to_mid, lines.sliceOfContent());

    try lines.replaceAllWith(original_text);
    try buffer.deleteRows(2, 4);
    try std.testing.expectEqualStrings(mid_to_mid, lines.sliceOfContent());

    try lines.replaceAllWith(original_text);
    try buffer.deleteRows(2, 5);
    try std.testing.expectEqualStrings(mid_to_end, lines.sliceOfContent());

    try lines.replaceAllWith(original_text);
    try buffer.deleteRows(1, 1);
    try std.testing.expectEqualStrings(same_line, lines.sliceOfContent());
}

test "undo and redo delete()" {
    const original_text =
        \\hello there my friend
        \\this ههههههه is a test إختبار text with UTF-8 mixed in.
        \\with three lines!!!!
        \\
    ; // the editor always insures a newline at is the end

    const deleted_whole_line =
        \\hello there my friend
        \\with three lines!!!!
        \\
    ;

    const deleted_within_line =
        \\hello there my friend
        \\this هتبار text with UTF-8 mixed in.
        \\with three lines!!!!
        \\
    ;

    var buffer = try Buffer.init(allocator, "", original_text);

    {
        try buffer.delete(2, 1, 999);
        try expectEqualStrings(deleted_whole_line, buffer.lines.sliceOfContent());

        try history.undo(buffer);
        try expectEqualStrings(original_text, buffer.lines.sliceOfContent());

        try history.redo(buffer);
        try expectEqualStrings(deleted_whole_line, buffer.lines.sliceOfContent());
    }

    try buffer.lines.replaceAllWith(original_text);

    {
        try buffer.delete(2, 7, 26);
        try expectEqualStrings(deleted_within_line, buffer.lines.sliceOfContent());

        try history.undo(buffer);
        try expectEqualStrings(original_text, buffer.lines.sliceOfContent());

        try history.redo(buffer);
        try expectEqualStrings(deleted_within_line, buffer.lines.sliceOfContent());
    }

    buffer.deinit();
}

test "undo and redo deleteRows()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ;

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
    var lines = &buffer.lines;
    defer buffer.deinit();

    {
        try buffer.deleteRows(1, 5);
        try expectEqualStrings(begin_to_end, lines.sliceOfContent());
        try history.undo(buffer);
        try expectEqualStrings(original_text, lines.sliceOfContent());
        try history.redo(buffer);
        try expectEqualStrings(begin_to_end, lines.sliceOfContent());
    }

    try lines.replaceAllWith(original_text);

    {
        try buffer.deleteRows(1, 3);
        try expectEqualStrings(begin_to_mid, lines.sliceOfContent());
        try history.undo(buffer);
        try expectEqualStrings(original_text, lines.sliceOfContent());
        try history.redo(buffer);
        try expectEqualStrings(begin_to_mid, lines.sliceOfContent());
    }

    try lines.replaceAllWith(original_text);

    {
        try buffer.deleteRows(2, 4);
        try expectEqualStrings(mid_to_mid, lines.sliceOfContent());
        try history.undo(buffer);
        try expectEqualStrings(original_text, lines.sliceOfContent());
        try history.redo(buffer);
        try expectEqualStrings(mid_to_mid, lines.sliceOfContent());
    }

    try lines.replaceAllWith(original_text);

    {
        try buffer.deleteRows(2, 5);
        try expectEqualStrings(mid_to_end, lines.sliceOfContent());
        try history.undo(buffer);
        try expectEqualStrings(original_text, lines.sliceOfContent());
        try history.redo(buffer);
        try expectEqualStrings(mid_to_end, lines.sliceOfContent());
    }

    try lines.replaceAllWith(original_text);

    {
        try buffer.deleteRows(1, 1);
        try expectEqualStrings(same_line, lines.sliceOfContent());
        try history.undo(buffer);
        try expectEqualStrings(original_text, lines.sliceOfContent());
        try history.redo(buffer);
        try expectEqualStrings(same_line, lines.sliceOfContent());
    }
}
