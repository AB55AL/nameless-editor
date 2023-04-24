const std = @import("std");

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const untils = @import("../utils.zig");

const Hooks = @This();

// Make sure Sets and Kind have identical member names
comptime {
    const kind_fields_names = std.meta.fieldNames(Kind);
    const sets_fields_names = std.meta.fieldNames(Sets);

    if (kind_fields_names.len != sets_fields_names.len)
        @compileError("Hooks.Kind and Hooks.Sets must have identical member names and count");

    outer_loop: for (kind_fields_names) |kind_name| {
        for (sets_fields_names) |set_name| {
            if (std.mem.eql(u8, kind_name, set_name))
                continue :outer_loop;
        }

        @compileError("Hooks.Kind." ++ kind_name ++ " Doesn't exist in Sets.");
    }
}

pub const Sets = struct {
    const Set = std.AutoArrayHashMapUnmanaged;
    after_insert: Set(*const Kind.AfterInsert, void) = .{},
    after_delete: Set(*const Kind.AfterDelete, void) = .{},
};

pub const Kind = enum {
    after_insert,
    after_delete,

    pub fn fieldName(kind: Kind) []const u8 {
        const fields = @typeInfo(Kind).Enum.fields;
        inline for (fields) |field| {
            if (field.value == @enumToInt(kind))
                return field.name;
        }

        unreachable;
    }

    pub const AfterInsert = fn (before: Buffer.Change, after: Buffer.Change) void;
    pub const AfterDelete = fn (before: Buffer.Change, after: Buffer.Change) void;
};

sets: Sets = .{},
allocator: std.mem.Allocator,

pub fn init(allocator: std.mem.Allocator) Hooks {
    return .{ .allocator = allocator };
}

pub fn deinit(hooks: *Hooks) void {
    const sets_fields = @typeInfo(Hooks.Sets).Struct.fields;
    inline for (sets_fields) |field|
        @field(hooks.sets, field.name).deinit(hooks.allocator);
}

pub fn attach(hooks: *Hooks, comptime kind: Kind, function: anytype) void {
    _ = (@field(hooks.sets, kind.fieldName())).getOrPut(hooks.allocator, function) catch return;
}

pub fn detach(hooks: *Hooks, comptime kind: Kind, function: anytype) void {
    _ = @field(hooks.sets, kind.fieldName()).swapRemove(function);
}

pub fn dispatch(hooks: *Hooks, comptime kind: Kind, args: anytype) void {
    var iter = @field(hooks.sets, kind.fieldName()).iterator();
    while (iter.next()) |kv| @call(.never_inline, (kv.key_ptr.*), args);
}
