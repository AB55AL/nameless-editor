const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const untils = @import("../utils.zig");
const BufferHandle = @import("../core.zig").BufferHandle;

pub fn GenerateHooks(comptime KindEnum: type, comptime Interfaces: type) type {
    const interfaces = std.meta.fields(Interfaces);
    const enums = std.meta.fields(KindEnum);

    if (interfaces.len != enums.len) @compileError("Interfaces And Enums must be of the same length");

    outer_loop: for (enums) |e| {
        for (interfaces) |i| {
            if (std.mem.eql(u8, e.name, i.name))
                continue :outer_loop;
        }

        @compileError("enum '" ++ e.name ++ "' Doesn't exist in " ++ @typeName(Interfaces));
    }

    for (interfaces) |i| {
        if (@typeInfo(i.type) != .Struct) @compileError("Interfaces must be a Struct");
        if (std.ascii.isDigit(i.name[0])) @compileError("Every member in Interfaces must have a name that doesn't start with a digit");
    }

    for (interfaces) |i| {
        if (!@hasDecl(i.type, "call"))
            @compileError("All interface must have a call function but '" ++ i.name ++ "' does not");
    }

    const GeneratedSets = blk: {
        const StructField = std.builtin.Type.StructField;
        var fields: []const StructField = &[_]StructField{};

        for (std.meta.fields(KindEnum), 0..) |field, index| {
            const IType = interfaces[index].type;
            const Data = ArrayListUnmanaged(IType);
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
            inline for (std.meta.fields(GeneratedSets)) |field|
                @field(self.sets, field.name).deinit(self.allocator);
        }

        pub fn attach(self: *Self, comptime kind: KindEnum, interface: anytype) !void {
            if (self.exists(kind, interface)) return;
            try @field(self.sets, fieldName(kind)).append(self.allocator, interface); // an error here means the *caller* has provided the wrong interface type
        }

        pub fn detach(self: *Self, comptime kind: KindEnum, function: anytype) void {
            _ = @field(self.sets, fieldName(kind)).swapRemove(function);
        }

        pub fn dispatch(self: *Self, comptime kind: KindEnum, args: anytype) void {
            for ((@field(self.sets, fieldName(kind))).items) |interface|
                @call(.never_inline, @field(interface, "call"), args); // an error here means the *caller* has provided the wrong function args
        }

        fn exists(self: *Self, comptime kind: KindEnum, interface: anytype) bool {
            for ((@field(self.sets, fieldName(kind))).items) |inter|
                if (std.meta.eql(inter, interface)) return true;

            return false;
        }

        fn fieldName(comptime kind: KindEnum) []const u8 {
            const fields = std.meta.fields(KindEnum);
            inline for (fields) |field|
                if (field.value == @enumToInt(kind)) return field.name;

            unreachable;
        }

        pub fn interfaceType(comptime kind: KindEnum) type {
            const kind_name = fieldName(kind);

            const fields = std.meta.fields(GeneratedSets);
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, kind_name)) {
                    //
                    const ArrayList = @typeInfo(field.type).Struct;
                    for (ArrayList.fields) |af| {
                        if (std.mem.eql(u8, af.name, "items")) {
                            const ArrayListType = af.type;
                            const child_type = @typeInfo(ArrayListType).Pointer.child;
                            return child_type;
                        }
                    }
                    //
                }
            }

            unreachable;
        }
    };
}

pub const EditorHooks = GenerateHooks(Kind, EditorInterfaces);
pub const EditorInterfaces = struct {
    buffer_created: BufferCreated,
    after_insert: Change,
    after_delete: Change,

    const Change = struct {
        ptr: *anyopaque,
        vtable: *const VTable,
        const VTable = struct {
            call: *const fn (ptr: *anyopaque, buffer: *Buffer, bhandle: ?BufferHandle, change: Buffer.Change) void,
        };
        pub fn call(self: Change, buffer: *Buffer, bhandle: ?BufferHandle, change: Buffer.Change) void {
            self.vtable.call(self.ptr, buffer, bhandle, change);
        }
    };

    const BufferCreated = struct {
        ptr: *anyopaque,
        vtable: *const VTable,
        const VTable = struct {
            call: *const fn (ptr: *anyopaque, buffer: *Buffer, bhandle: BufferHandle) void,
        };
        pub fn call(self: BufferCreated, buffer: *Buffer, bhandle: BufferHandle) void {
            self.vtable.call(self.ptr, buffer, bhandle);
        }
    };
};
const Kind = enum {
    buffer_created,
    after_insert,
    after_delete,
};
