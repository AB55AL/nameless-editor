const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;
const count = std.mem.count;

const mecha = @import("mecha");

const Buffer = @import("buffer.zig");
const default_commands = @import("default_commands.zig");
const buffer_ops = @import("../editor/buffer_ops.zig");
const buffer_window = @import("../ui/buffer_window.zig");
const notify = @import("../ui/notify.zig");

pub const FuncType = *const fn ([]PossibleValues) CommandRunError!void;
pub const CommandType = struct {
    function: FuncType,
    description: []const u8,
};

const globals = @import("../globals.zig");
const ui = globals.ui;
const editor = globals.editor;
const internal = globals.internal;

const ParseError = error{
    DoubleQuoteInvalidPosition,
    InvalidNumberOfDoubleQuote,
    ContainsInvalidValues,
};

const CommandRunError = error{
    FunctionCommandMismatchedTypes,
    ExtraArgs,
    MissingArgs,
};

const PossibleValues = union(enum) {
    int: i64,
    string: []const u8,
    float: f64,
    bool: bool,

    pub fn sameType(pv: PossibleValues, T: anytype) bool {
        return switch (pv) {
            .float, .int => (@typeInfo(T) == .Int or @typeInfo(T) == .Float),
            inline else => |v| std.meta.eql(@TypeOf(v), T),
        };
    }
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
    editor.command_function_lut = std.StringHashMap(CommandType).init(internal.allocator);
    try default_commands.setDefaultCommands();
}

pub fn deinit() void {
    editor.command_function_lut.deinit();
}

pub fn open() void {
    editor.command_line_is_open = true;
    if (ui.focused_buffer_window) |fbw| buffer_ops.pushAsPreviousBufferWindow(fbw);
    ui.focused_buffer_window = &ui.command_line_buffer_window;
}

pub fn close(pop_previous_window: bool, focus_buffers: bool) void {
    editor.command_line_is_open = false;
    editor.command_line_buffer.clear() catch |err| {
        print("cloudn't clear command_line buffer err={}", .{err});
    };

    if (pop_previous_window) ui.focused_buffer_window = buffer_ops.popPreviousFocusedBufferWindow();
    if (focus_buffers) ui.focus_buffers = true;
}

pub fn run() !void {
    var command_str: [4096]u8 = undefined;
    var len = editor.command_line_buffer.size();

    const command_line_content = try editor.command_line_buffer.getAllLines(internal.allocator);
    defer internal.allocator.free(command_line_content);
    std.mem.copy(u8, &command_str, command_line_content);

    close(true, true);
    runCommand(command_str[0 .. len - 1]);
}

pub fn add(comptime command: []const u8, comptime fn_ptr: anytype, comptime description: []const u8) !void {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;
    if (fn_info.return_type.? != void)
        @compileError("The command's function return type needs to be void");
    if (fn_info.is_var_args)
        @compileError("The command's function cannot be variadic");

    comptime if (count(u8, command, " ") > 0) @compileError("The command name shouldn't have a space");

    try editor.command_function_lut.put(command, .{
        .function = beholdMyFunctionInator(fn_ptr).funcy,
        .description = description,
    });
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
    const com = editor.command_function_lut.get(command);

    if (com) |c| {
        c.function(args) catch |err| {
            const err_msg = switch (err) {
                CommandRunError.FunctionCommandMismatchedTypes => "The command argument type does not match the function",
                CommandRunError.ExtraArgs => "Extra arguments\n",
                CommandRunError.MissingArgs => "Missing arguments\n",
            };

            notify.notify("Command Line Error:", err_msg, 3);
        };
    } else {
        notify.notify("Command Line Error:", "The command doesn't exist", 3);
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
                inline for (args_tuple, 0..) |_, index| {
                    if (!args[index].sameType(@TypeOf(args_tuple[index]))) {
                        return CommandRunError.FunctionCommandMismatchedTypes;
                    }

                    const ArgTupleType = @TypeOf(args_tuple[index]);
                    const argtuple_type_info = @typeInfo(ArgTupleType);

                    if (args[index] == .int and (argtuple_type_info == .Int or argtuple_type_info == .Float)) {
                        if (argtuple_type_info == .Int)
                            args_tuple[index] = @intCast(ArgTupleType, args[index].int)
                        else {
                            args_tuple[index] = @intToFloat(ArgTupleType, args[index].int);
                        }
                    } else if (args[index] == .float and argtuple_type_info == .Float) {
                        args_tuple[index] = @floatCast(ArgTupleType, args[index].float);
                    } else if (args[index] == .float and argtuple_type_info == .Int) {
                        args_tuple[index] = @floatToInt(ArgTupleType, args[index].float);
                    } else if (args[index] == .string and std.meta.eql(ArgTupleType, []const u8)) {
                        args_tuple[index] = args[index].string;
                    } else if (args[index] == .bool and std.meta.eql(ArgTupleType, bool)) {
                        args_tuple[index] = args[index].bool;
                    }
                }

                @call(.never_inline, function, args_tuple);
            } else if (args.len < fn_info.params.len) {
                return CommandRunError.MissingArgs;
            } else if (args.len > fn_info.params.len) {
                return CommandRunError.ExtraArgs;
            }
        }
    };
}

const parseCommand = mecha.combine(.{
    mecha.many(mecha.utf8.not(mecha.utf8.char(' ')), .{ .collect = false }),
    discardManyWhiteSpace,
});

const parseArgs = mecha.combine(.{
    mecha.oneOf(.{
        parseBool,
        parseInt,
        parseFloat,
        parseString,
        parseQuotlessString,
    }),
    discardManyWhiteSpace,
});

const parseBool = mecha.map(toBool, mecha.combine(.{
    mecha.many(mecha.oneOf(.{
        mecha.string("true"),
        mecha.string("false"),
    }), .{ .max = 1, .collect = false }),

    discardWhiteSpace,
}));

const parseString = mecha.map(toString, mecha.combine(.{
    mecha.discard(mecha.utf8.char('"')),
    mecha.many(mecha.utf8.not(mecha.utf8.char('"')), .{ .collect = false }),
    mecha.discard(mecha.utf8.char('"')),
}));

const parseQuotlessString = mecha.map(toString, mecha.many(mecha.utf8.not(mecha.ascii.whitespace), .{ .collect = false }));

const parseFloat = mecha.convert(toFloat, mecha.many(mecha.oneOf(.{
    mecha.ascii.char('-'),
    mecha.ascii.digit(10),
    mecha.ascii.char('.'),
}), .{ .collect = false }));

const parseInt = mecha.convert(toInt, mecha.combine(.{
    mecha.many(mecha.oneOf(.{
        mecha.ascii.char('-'),
        mecha.ascii.digit(10),
    }), .{ .collect = false }),
    discardWhiteSpace,
}));

const discardWhiteSpace = mecha.discard(mecha.ascii.whitespace);
const discardManyWhiteSpace = mecha.discard(mecha.many(discardWhiteSpace, .{ .collect = false }));

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

fn toInt(allocator: std.mem.Allocator, string: []const u8) mecha.Error!PossibleValues {
    _ = allocator;
    const value = std.fmt.parseInt(i64, string, 10) catch |err| blk: {
        if (err == error.Overflow) {
            if (string[0] == '-')
                break :blk @intCast(i64, std.math.minInt(i64))
            else
                break :blk @intCast(i64, std.math.maxInt(i64));
        }

        return mecha.Error.ParserFailed;
    };
    return .{ .int = value };
}
