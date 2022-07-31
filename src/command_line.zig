const std = @import("std");
const print = @import("std").debug.print;
const ArrayList = std.ArrayList;
const count = std.mem.count;
const fmt = std.fmt;
const eqlIgnoreCase = std.ascii.eqlIgnoreCase;
const ascii = std.ascii;

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
    global.command_line_is_open = true;
    previous_buffer = global.focused_buffer;
    global.focused_buffer = global.command_line_buffer;
}

pub fn close() void {
    global.command_line_is_open = false;
    global.focused_buffer = previous_buffer;
    global.command_line_buffer.clear() catch |err| {
        print("cloudn't clear command_line buffer err={}", .{err});
    };
    Cursor.moveAbsolute(global.command_line_buffer, 1, 1);
}

pub fn run() void {
    var command_str: [4096]u8 = undefined;
    var len = global.command_line_buffer.lines.length();

    for (global.command_line_buffer.lines.slice(0, len)) |b, i|
        command_str[i] = b;

    close();
    runCommand(command_str[0 .. len - 1]);
}

pub fn add(comptime command: []const u8, comptime fn_ptr: anytype) !void {
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

fn runCommand(command_string: []const u8) void {
    var arena = std.heap.ArenaAllocator.init(internal.allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    var parsed_string = parse(alloc, command_string) catch |err| {
        // TODO: Notify user instead of printing
        print("{}\n", .{err});
        return;
    };
    if (parsed_string.len > 128) {
        print("too many args for command\n", .{});
        return;
    }

    var command = parsed_string[0];
    if (parsed_string.len > 1) {
        var tokens: [128]Token = undefined;
        var tokens_num = stringToTokens(parsed_string[1..], &tokens);

        var values: [128]PossibleValues = undefined;
        var pv_num = tokensToValues(tokens[0..tokens_num], &values);

        call(command, values[0..pv_num]);
    } else {
        call(command, &[_]PossibleValues{});
    }
}

fn call(command: []const u8, args: []PossibleValues) void {
    const function = command_function_lut.get(command);

    if (function) |f| {
        f(args) catch |err| {
            // TODO: Notify user instead of printing
            if (err == CommandRunError.FunctionCommandMismatchedTypes)
                print("The command args do not match the function\n", .{});
        };
    } else {
        // TODO: Notify user instead of printing
        print("The command doesn't exist\n", .{});
    }
}

fn parse(allocator: std.mem.Allocator, string: []const u8) ![][]const u8 {
    var array = ArrayList([]const u8).init(allocator);

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

            var content = try std.mem.concat(allocator, u8, &[_][]const u8{
                array.pop(),
                " ",
                s,
            });
            try array.append(content);
        } else {
            try array.append(s);
        }
    }

    return array.items;
}

fn tokensToValues(tokens: []Token, pv: []PossibleValues) u16 {
    var i: u16 = 0;
    for (tokens) |token, index| {
        defer i += 1;
        switch (token.type) {
            Types.string => {
                pv[index] = .{ .string = token.content };
            },
            Types.int => {
                const val = fmt.parseInt(i64, token.content, 10) catch unreachable;
                pv[index] = .{ .int = val };
            },
            Types.float => {
                const val = fmt.parseFloat(f64, token.content) catch unreachable;
                pv[index] = .{ .float = val };
            },
            Types.bool => {
                if (token.content.len > 1) unreachable;
                var val = charToBool(token.content[0]);
                pv[index] = .{ .bool = val };
            },
        }
    }

    return i;
}

fn stringToTokens(args_str: [][]const u8, out_buffer: []Token) u16 {
    var num: u16 = 0;
    for (args_str) |arg, i| {
        defer num += 1;
        if (arg[0] == '"' and arg[arg.len - 1] == '"') {
            if (arg.len == 2) {
                out_buffer[i] = .{ .type = Types.string, .content = "" };
            } else {
                out_buffer[i] = .{ .type = Types.string, .content = arg[1 .. arg.len - 1] }; // strip the ""
            }
        } else if (eqlIgnoreCase(arg, "T") or eqlIgnoreCase(arg, "F")) {
            out_buffer[i] = .{ .type = Types.bool, .content = arg };
        } else if (isFloat(arg)) {
            out_buffer[i] = .{ .type = Types.float, .content = arg };
        } else if (isInt(arg)) {
            out_buffer[i] = .{ .type = Types.int, .content = arg };
        } else { // assume double-quote-less string
            out_buffer[i] = .{ .type = Types.string, .content = arg };
        }
    }

    return num;
}

fn isFloat(str: []const u8) bool {
    if (count(u8, str, ".") != 1) return false;
    for (str) |c| {
        if (ascii.isDigit(c) or c == '.')
            continue
        else
            return false;
    }

    return true;
}

fn isInt(str: []const u8) bool {
    for (str) |c| {
        if (ascii.isDigit(c))
            continue
        else
            return false;
    }

    return true;
}

fn charToBool(char: u8) bool {
    return if (char == 'T' or char == 't') true else false;
}

// TODO: Make this not ugly
fn beholdMyFunctionInator(comptime fn_ptr: anytype) type {
    const fn_info = @typeInfo(@TypeOf(fn_ptr)).Fn;

    return struct {
        fn funcy(args: []PossibleValues) CommandRunError!void {
            if (args.len > fn_info.args.len and args.len != 0) {
                print("Command args are greater than the functions args", .{});
                return;
            }
            switch (fn_info.args.len) {
                0 => fn_ptr(),
                else => {
                    if (args.len == 0) return;
                    switch (fn_info.args.len) {
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
                },
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
