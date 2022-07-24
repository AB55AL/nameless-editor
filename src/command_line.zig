const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;
const count = std.mem.count;
const fmt = std.fmt;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;

const GlobalInternal = @import("global_types.zig").GlobalInternal;
const Global = @import("global_types.zig").Global;
const Buffer = @import("buffer.zig");
const Cursor = @import("cursor.zig");
const default_commands = @import("default_commands.zig");

const FuncType = fn ([]PossibleValues) CommandRunError!void;

extern var internal: GlobalInternal;
extern var global: Global;

var command_function_lut: std.StringHashMap(FuncType) = undefined;
var previous_buffer: *Buffer = undefined;

const ParseError = error{
    DoubleQuoteInvalidPosition,
    InvalidNumberOfDoubleQuote,
    ContainsInvalidValues,
};

const CommandRunError = error{
    FunctionCommandMismatchedTypes,
};

const PossibleValuesTag = enum { int, string, float, bool };
const PossibleValues = union(PossibleValuesTag) {
    int: i64,
    string: []const u8,
    float: f64,
    bool: bool,
};

pub fn init() !void {
    command_function_lut = std.StringHashMap(FuncType).init(internal.allocator);
    try default_commands.setDefaultCommands();
}

pub fn deinit() void {
    command_function_lut.deinit();
}

pub fn openCommandLine() void {
    global.command_line_is_open = true;
    previous_buffer = global.focused_buffer;
    global.focused_buffer = global.command_line_buffer;
}

pub fn closeCommandLine() void {
    global.command_line_is_open = false;
    global.focused_buffer = previous_buffer;
    global.command_line_buffer.clear() catch |err| {
        print("cloudn't clear command_line buffer err={}", .{err});
    };
    Cursor.moveAbsolute(global.command_line_buffer, 1, 1);
}

pub fn runCommand() void {
    var command_str: [4096]u8 = undefined;
    var len = global.command_line_buffer.lines.length();

    for (global.command_line_buffer.lines.sliceOfContent()) |b, i|
        command_str[i] = b;

    closeCommandLine();
    run(command_str[0 .. len - 1]);
}

pub fn addCommand(comptime command: []const u8, comptime fn_ptr: anytype) !void {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;
    if (fn_info.return_type.? != void)
        @compileError("The command's function return type needs to be void");
    if (fn_info.args.len > 6)
        @compileError("The command's function should have at most 6 arguments");
    if (fn_info.is_var_args)
        @compileError("The command's function cannot be variadic");

    comptime {
        if (count(u8, command, " ") > 0)
            @compileError("The command name shouldn't have a space");
    }

    try command_function_lut.put(command, beholdMyFunctionInator(fn_ptr).funcy);
}

pub fn run(command_string: []const u8) void {
    var parsed_string = parse(command_string) catch |err| {
        // TODO: Notify user instead of printing
        print("{}\n", .{err});
        return;
    };
    defer internal.allocator.free(parsed_string);
    var command = parsed_string[0];

    if (parsed_string.len <= 1) return;

    var args = convertArgsToValues(parsed_string[1..]);
    defer internal.allocator.free(args);
    call(command, args);
}

fn call(command: []const u8, args: []PossibleValues) void {
    const function = command_function_lut.get(command);

    if (function) |f| {
        f(args) catch |err| {
            // TODO: Notify user instead of printing
            if (err == CommandRunError.FunctionCommandMismatchedTypes) {
                print("The command args do not match the function\n", .{});
            }
        };
    } else {
        // TODO: Notify user instead of printing
        print("The command doesn't exist\n", .{});
    }
}

fn parse(string: []const u8) ![][]const u8 {
    var array = ArrayList([]const u8).init(internal.allocator);
    var iter = std.mem.split(u8, string, " ");

    var double_q_num = count(u8, string, "\"");
    const escaped_double_q_num = count(u8, string, "\\\"");

    const dqn = double_q_num - escaped_double_q_num;
    if (dqn % 2 != 0) {
        return ParseError.InvalidNumberOfDoubleQuote;
    }

    while (iter.next()) |s| {
        if (array.items.len == 0) {
            try array.append(s);
            continue;
        }

        if (count(u8, s, "\"") > 2) {
            return ParseError.InvalidNumberOfDoubleQuote;
        }

        const top_of_stack = array.items[array.items.len - 1];
        double_q_num = count(u8, top_of_stack, "\"") - count(u8, top_of_stack, "\\\"");

        if (double_q_num == 1) {
            if (top_of_stack[0] != '"') {
                return ParseError.DoubleQuoteInvalidPosition;
            }
            var content = try std.mem.concat(internal.allocator, u8, &[_][]const u8{
                array.pop(),
                " ",
                s,
            });
            try array.append(content);
        } else {
            try array.append(s);
        }
    }

    for (array.items) |item, i| {
        if (i == 0) continue;
        if (item[0] == '"' and item[item.len - 1] == '"') continue;

        for (item) |char|
            if (!std.ascii.isDigit(char) and char != '.')
                return ParseError.ContainsInvalidValues;
    }

    return array.toOwnedSlice();
}

fn convertArgsToValues(args_str: [][]const u8) []PossibleValues {
    var args = internal.allocator.alloc(PossibleValues, args_str.len) catch unreachable;
    for (args_str) |arg, i| {
        if (arg[0] == '"' and arg[arg.len - 1] == '"') {
            if (arg.len == 2) {
                args[i] = .{ .string = "" };
            } else {
                args[i] = .{ .string = arg[1 .. arg.len - 1] }; // strip the ""
            }
        } else if (eqlIgnoreCase(arg, "true")) {
            args[i] = .{ .bool = true };
        } else if (eqlIgnoreCase(arg, "false")) {
            args[i] = .{ .bool = false };
        } else if (count(u8, arg, ".") == 1) {
            var float = fmt.parseFloat(f64, arg) catch unreachable;
            args[i] = .{ .float = float };
        } else {
            var int = fmt.parseInt(i64, arg, 10) catch unreachable;
            args[i] = .{ .int = int };
        }
    }

    return args;
}

// TODO: Make this not ugly
fn beholdMyFunctionInator(comptime fn_ptr: anytype) type {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;

    return struct {
        fn funcy(args: []PossibleValues) CommandRunError!void {
            if (args.len > fn_info.args.len) {
                print("Command args are greater than the functions args", .{});
                return;
            }
            switch (fn_info.args.len) {
                0 => fn_ptr(),
                1 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                ),
                2 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                    try argHandler(fn_info, args[1], 1),
                ),
                3 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                    try argHandler(fn_info, args[1], 1),
                    try argHandler(fn_info, args[2], 2),
                ),
                4 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                    try argHandler(fn_info, args[1], 1),
                    try argHandler(fn_info, args[2], 2),
                    try argHandler(fn_info, args[3], 3),
                ),
                5 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                    try argHandler(fn_info, args[1], 1),
                    try argHandler(fn_info, args[2], 2),
                    try argHandler(fn_info, args[3], 3),
                    try argHandler(fn_info, args[4], 4),
                ),
                6 => fn_ptr(
                    try argHandler(fn_info, args[0], 0),
                    try argHandler(fn_info, args[1], 1),
                    try argHandler(fn_info, args[2], 2),
                    try argHandler(fn_info, args[3], 3),
                    try argHandler(fn_info, args[4], 4),
                    try argHandler(fn_info, args[5], 5),
                ),
                else => unreachable,
            }
        }
    };
}

fn argHandler(comptime fn_info: std.builtin.Type.Fn, value: PossibleValues, comptime index: usize) !fn_info.args[index].arg_type.? {
    const arg_type = fn_info.args[index].arg_type.?;
    const val = switch (value) {
        .string => |v| if (@TypeOf(v) == arg_type) return v else return CommandRunError.FunctionCommandMismatchedTypes,
        .bool => |v| if (@TypeOf(v) == arg_type) return v else return CommandRunError.FunctionCommandMismatchedTypes,
        .int => |v| if (arg_type == u32 or arg_type == u64 or arg_type == i32 or arg_type == i64) return @intCast(arg_type, v) else return CommandRunError.FunctionCommandMismatchedTypes,
        .float => |v| if (arg_type == f32 or arg_type == f64) return @floatCast(arg_type, v) else CommandRunError.FunctionCommandMismatchedTypes,
    };
    return val;
}
