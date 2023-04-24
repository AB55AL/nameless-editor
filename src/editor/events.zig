const std = @import("std");

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const untils = @import("../utils.zig");

const Events = @This();

// Make sure Sets and Kind have identical member names
comptime {
    const kind_fields_names = std.meta.fieldNames(Kind);
    const sets_fields_names = std.meta.fieldNames(Sets);

    if (kind_fields_names.len != sets_fields_names.len)
        @compileError("Events.Kind and Events.Sets must have identical member names and count");

    outer_loop: for (kind_fields_names) |kind_name| {
        for (sets_fields_names) |set_name| {
            if (std.mem.eql(u8, kind_name, set_name))
                continue :outer_loop;
        }

        @compileError("Events.Kind." ++ kind_name ++ " Doesn't exist in Sets.");
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

pub fn init(allocator: std.mem.Allocator) Events {
    return .{ .allocator = allocator };
}

pub fn deinit(events: *Events) void {
    const sets_fields = @typeInfo(Events.Sets).Struct.fields;
    inline for (sets_fields) |field|
        @field(events.sets, field.name).deinit(events.allocator);
}

pub fn attach(events: *Events, comptime kind: Kind, function: anytype) void {
    _ = (@field(events.sets, kind.fieldName())).getOrPut(events.allocator, function) catch return;
}

pub fn detach(events: *Events, comptime kind: Kind, function: anytype) void {
    _ = @field(events.sets, kind.fieldName()).swapRemove(function);
}

pub fn dispatch(events: *Events, comptime kind: Kind, args: anytype) void {
    var iter = @field(events.sets, kind.fieldName()).iterator();
    while (iter.next()) |kv| @call(.never_inline, (kv.key_ptr.*), args);
}
