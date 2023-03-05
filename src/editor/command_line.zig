const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;
const count = std.mem.count;

const mecha = @import("mecha");

const Buffer = @import("buffer.zig");
const default_commands = @import("default_commands.zig");
const buffer_ops = @import("../editor/buffer_ops.zig");
const buffer_ui = @import("../ui/buffer.zig");
const notify = @import("../ui/notify.zig");

const FuncType = *const fn ([]PossibleValues) CommandRunError!void;

const globals = @import("../globals.zig");
const ui = globals.ui;
const editor = globals.editor;
const internal = globals.internal;

var command_function_lut: std.StringHashMap(FuncType) = undefined;

const ParseError = error{
    DoubleQuoteInvalidPosition,
    InvalidNumberOfDoubleQuote,
    ContainsInvalidValues,
};

const CommandRunError = error{
    FunctionCommandMismatchedTypes,
};

const PossibleValues = union(enum) {
    int: i64,
    string: []const u8,
    float: f64,
    bool: bool,
};

const Token = struct {
    type: Types,
    content: []const u8,
};

const Types = enum {
    string,
    int,
    float,
    bool,
};

pub fn init() !void {
    command_function_lut = std.StringHashMap(FuncType).init(internal.allocator);
    try default_commands.setDefaultCommands();
}

pub fn deinit() void {
    command_function_lut.deinit();
}

pub fn open() void {
    editor.command_line_is_open = true;
    if (ui.focused_buffer_window) |fbw| buffer_ops.pushAsPreviousBufferWindow(fbw);
    ui.focused_buffer_window = &ui.command_line_buffer_window;
}

pub fn close() void {
    editor.command_line_is_open = false;
    ui.focused_buffer_window = buffer_ops.popPreviousFocusedBufferWindow();
    editor.command_line_buffer.clear() catch |err| {
        print("cloudn't clear command_line buffer err={}", .{err});
    };
}

pub fn run() !void {
    var command_str: [4096]u8 = undefined;
    var len = editor.command_line_buffer.lines.size;

    const command_line_content = try editor.command_line_buffer.getAllLines(internal.allocator);
    defer internal.allocator.free(command_line_content);
    std.mem.copy(u8, &command_str, command_line_content);

    close();
    runCommand(command_str[0..len]);
}

pub fn add(comptime command: []const u8, comptime fn_ptr: anytype) !void {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;
    if (fn_info.return_type.? != void)
        @compileError("The command's function return type needs to be void");
    if (fn_info.is_var_args)
        @compileError("The command's function cannot be variadic");

    comptime if (count(u8, command, " ") > 0) @compileError("The command name shouldn't have a space");

    try command_function_lut.put(command, beholdMyFunctionInator(fn_ptr).funcy);
}

fn runCommand(command_string: []const u8) void {
    const allocator = internal.allocator;

    const command_result = parseCommand(allocator, command_string) catch |err| {
        print("{}\n", .{err});
        return;
    };
    var command = command_result.value;

    var buffer: [128]PossibleValues = undefined;
    var string = command_result.rest;
    var i: u32 = 0;
    while (string.len != 0) : (i += 1) {
        var result = parseArgs(allocator, string) catch |err| {
            print("{}\n", .{err});
            return;
        };
        buffer[i] = result.value;
        string = result.rest;
    }

    call(command, buffer[0..i]);
}

fn call(command: []const u8, args: []PossibleValues) void {
    const function = command_function_lut.get(command);

    if (function) |f| {
        f(args) catch |err| {
            if (err == CommandRunError.FunctionCommandMismatchedTypes) {
                print("The command args do not match the function\n", .{});
                notify.notify("Command Line Error:", "The command args do not match the function", 3000);
            }
        };
    } else {
        notify.notify("Command Line Error:", "The command doesn't exist", 3000);
    }
}

fn beholdMyFunctionInator(comptime function: anytype) type {
    const fn_info = @typeInfo(@TypeOf(function)).Fn;

    return struct {
        fn funcy(args: []PossibleValues) CommandRunError!void {
            if (fn_info.params.len == 0) {
                function();
            } else if (args.len > 0 and args.len == fn_info.params.len) {
                const Tuple = std.meta.ArgsTuple(@TypeOf(function));
                var args_tuple: Tuple = undefined;
                inline for (args_tuple, 0..) |_, index|
                    args_tuple[index] = try argHandler(fn_info, args[index], index);

                @call(.never_inline, function, args_tuple);
            } else {
                unreachable;
            }
        }
    };
}

fn argHandler(comptime fn_info: std.builtin.Type.Fn, value: PossibleValues, comptime index: usize) !fn_info.params[index].type.? {
    const arg_type = fn_info.params[index].type.?;
    const val = switch (value) {
        .string => |v| if (@TypeOf(v) == arg_type) return v else return CommandRunError.FunctionCommandMismatchedTypes,
        .bool => |v| if (@TypeOf(v) == arg_type) return v else return CommandRunError.FunctionCommandMismatchedTypes,
        .int => |v| if (arg_type == u32 or arg_type == u64 or arg_type == i32 or arg_type == i64) return @intCast(arg_type, v) else return CommandRunError.FunctionCommandMismatchedTypes,
        .float => |v| if (arg_type == f32 or arg_type == f64) return @floatCast(arg_type, v) else CommandRunError.FunctionCommandMismatchedTypes,
    };
    return val;
}

const parseCommand = mecha.combine(.{
    mecha.many(mecha.utf8.not(mecha.utf8.char(' ')), .{ .collect = false }),
    discardWhiteSpace,
});

const parseArgs = mecha.combine(.{
    mecha.oneOf(.{
        parseBool,
        parseNumber,
        parseString,
        parseQuotlessString,
    }),
    discardWhiteSpace,
});

const parseBool = mecha.map(toBool, mecha.combine(.{
    mecha.many(mecha.oneOf(.{
        mecha.string("true"),
        mecha.string("false"),
    }), .{ .max = 1, .collect = false }),

    mecha.discard(mecha.oneOf(.{
        mecha.utf8.char(' '),
        mecha.utf8.char('\n'),
    })),
}));

const parseString = mecha.map(toString, mecha.combine(.{
    mecha.discard(mecha.utf8.char('"')),
    mecha.many(mecha.utf8.not(mecha.utf8.char('"')), .{ .collect = false }),
    mecha.discard(mecha.utf8.char('"')),
}));

const parseQuotlessString = mecha.map(toString, mecha.many(mecha.utf8.not(mecha.utf8.char(' ')), .{ .collect = false }));

const parseNumber = mecha.convert(toFloat, mecha.many(mecha.oneOf(.{
    mecha.ascii.digit(10),
    mecha.ascii.char('.'),
}), .{ .collect = false }));

const discardWhiteSpace = mecha.discard(mecha.many(mecha.ascii.whitespace, .{ .collect = false }));

fn toBool(string: []const u8) PossibleValues {
    return .{ .bool = std.mem.eql(u8, "true", string) };
}

fn toString(string: []const u8) PossibleValues {
    return .{ .string = string };
}

fn toFloat(allocator: std.mem.Allocator, string: []const u8) mecha.Error!PossibleValues {
    _ = allocator;
    return .{ .float = std.fmt.parseFloat(f64, string) catch return mecha.Error.ParserFailed };
}
