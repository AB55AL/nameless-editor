const std = @import("std");

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const untils = @import("../utils.zig");

pub fn GenerateHooks(comptime KindEnum: type, comptime FunctionsStruct: type) type {
    const funcs = std.meta.fields(FunctionsStruct);
    const enums = std.meta.fields(KindEnum);

    if (funcs.len != enums.len) @compileError("FunctionsStruct And Enums must be of the same length");

    outer_loop: for (enums) |e| {
        for (funcs) |f| {
            if (std.mem.eql(u8, e.name, f.name))
                continue :outer_loop;
        }

        @compileError("enum '" ++ e.name ++ "' Doesn't exist in " ++ @typeName(FunctionsStruct));
    }

    for (funcs) |f| {
        if (@typeInfo(f.type) != .Fn) @compileError("FunctionsStruct must have only function types");
        if (std.ascii.isDigit(f.name[0])) @compileError("Every member in FunctionsStruct must have a name that doesn't start with a digit");
    }

    const Set = std.AutoArrayHashMapUnmanaged;
    const GeneratedSets = blk: {
        const StructField = std.builtin.Type.StructField;
        var fields: []const StructField = &[_]StructField{};

        for (std.meta.fields(KindEnum), 0..) |field, index| {
            const FnType = *const funcs[index].type;
            const Data = Set(FnType, void);
            fields = fields ++ &[_]StructField{.{
                .name = field.name,
                .type = Data,
                .default_value = @ptrCast(*const anyopaque, &Data{}),
                .is_comptime = false,
                .alignment = @alignOf(Data),
            }};
        }

        break :blk @Type(.{ .Struct = .{
            .layout = .Auto,
            .fields = fields,
            .decls = &.{},
            .is_tuple = false,
        } });
    };

    return struct {
        const Self = @This();

        sets: GeneratedSets = .{},
        allocator: std.mem.Allocator,

        pub fn init(allocator: std.mem.Allocator) Self {
            return .{ .allocator = allocator };
        }

        pub fn deinit(self: *Self) void {
            const sets_fields = @typeInfo(GeneratedSets).Struct.fields;
            inline for (sets_fields) |field|
                @field(self.sets, field.name).deinit(self.allocator);
        }

        pub fn attach(self: *Self, comptime kind: KindEnum, function: anytype) void {
            _ = (@field(self.sets, fieldName(kind))).getOrPut(self.allocator, function) catch return;
        }

        pub fn detach(self: *Self, comptime kind: KindEnum, function: anytype) void {
            _ = @field(self.sets, fieldName(kind)).swapRemove(function);
        }

        pub fn dispatch(self: *Self, comptime kind: KindEnum, args: anytype) void {
            var iter = @field(self.sets, fieldName(kind)).iterator();
            while (iter.next()) |kv| @call(.never_inline, (kv.key_ptr.*), args);
        }

        fn fieldName(comptime kind: KindEnum) []const u8 {
            const fields = std.meta.fields(KindEnum);
            inline for (fields) |field|
                if (field.value == @enumToInt(kind)) return field.name;

            unreachable;
        }
    };
}

pub const EditorHooks = GenerateHooks(Kind, Functions);
const Functions = struct {
    after_insert: fn (before: Buffer.Change, after: Buffer.Change) void,
    after_delete: fn (before: Buffer.Change, after: Buffer.Change) void,
};
const Kind = enum {
    after_insert,
    after_delete,
};
