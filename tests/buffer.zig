const std = @import("std");
const expect = std.testing.expect;
const allocator = std.testing.allocator;
const print = std.debug.print;

const core = @import("core");
const Buffer = core.Buffer;
const history = core.history;

test "deleteRange()" {
    const original_text =
        \\hello there my friend
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
    ;

    const string_after_change =
        \\hello there my friend
        \\tدهش Amazing isn't it ?!
        \\
    ; // the editor always insures a newline at is the end

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
    ;

    const begin_to_end = "\n"; // the editor always insures a newline at is the end

    const begin_to_mid =
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ; // the editor always insures a newline at is the end
    const mid_to_mid =
        \\hello there my friend
        \\And heres some more
        \\
    ; // the editor always insures a newline at is the end
    const mid_to_end =
        \\hello there my friend
        \\
    ; // the editor always insures a newline at is the end

    const same_line =
        \\this is a test text.
        \\with UTF-8 نعم ، إنه مدهش Amazing isn't it ?!
        \\Oh! we got a another line here
        \\And heres some more
        \\
    ; // the editor always insures a newline at is the end

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
