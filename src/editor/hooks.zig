const std = @import("std");
const ArrayListUnmanaged = std.ArrayListUnmanaged;

const globals = @import("../globals.zig");
const Buffer = @import("buffer.zig");
const untils = @import("../utils.zig");
const BufferHandle = @import("../core.zig").BufferHandle;

pub fn GenerateHooks(comptime Interfaces: type) type {
    const interfaces = std.meta.fields(Interfaces);

    for (interfaces) |i| {
        if (@typeInfo(i.type) != .Struct) @compileError("Interfaces must be a Struct");
        if (std.ascii.isDigit(i.name[0])) @compileError("Every member in Interfaces must have a name that doesn't start with a digit");
    }

    for (interfaces) |i| {
        if (!@hasDecl(i.type, "call"))
            @compileError("All interface must have a call function but '" ++ i.name ++ "' does not");

        if (!@hasField(i.type, "call_fn"))
            @compileError("All interface must have a call_fn member but '" ++ i.name ++ "' does not");
    }

    const GeneratedSets = blk: {
        const StructField = std.builtin.Type.StructField;
        var fields: []const StructField = &[_]StructField{};

        for (std.meta.fields(Interfaces)) |field| {
            const IType = field.type;
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

        pub fn attach(self: *Self, comptime kind: []const u8, interface: anytype) !void {
            comptime verifyKind(kind);
            if (self.exists(kind, interface)) return;
            try @field(self.sets, kind).append(self.allocator, interface); // an error here means the *caller* has provided the wrong interface type
        }

        pub fn detach(self: *Self, comptime kind: []const u8, function: anytype) void {
            comptime verifyKind(kind);
            _ = @field(self.sets, kind).swapRemove(function);
        }

        pub fn dispatch(self: *Self, comptime kind: []const u8, args: anytype) void {
            comptime verifyKind(kind);
            for ((@field(self.sets, kind)).items) |interface|
                @call(.auto, interfaceType(kind).call, .{interface} ++ args); // an error here means the *caller* has provided the wrong function args
        }

        pub fn createAndAttach(self: *Self, comptime kind: []const u8, ptr: anytype, call: anytype) !void {
            comptime verifyKind(kind);
            var int = createInterface(kind, ptr, call);
            try self.attach(kind, int);
        }

        pub fn createInterface(comptime kind: []const u8, ptr: anytype, call: anytype) interfaceType(kind) {
            comptime verifyKind(kind);
            return interfaceType(kind){
                .ptr = @ptrCast(*anyopaque, @alignCast(1, ptr)),
                .call_fn = call,
            };
        }

        pub fn interfaceType(comptime kind: []const u8) type {
            comptime verifyKind(kind);
            const fields = std.meta.fields(GeneratedSets);
            inline for (fields) |field| {
                if (std.mem.eql(u8, field.name, kind)) {
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

        fn exists(self: *Self, comptime kind: []const u8, interface: anytype) bool {
            for ((@field(self.sets, kind)).items) |inter|
                if (std.meta.eql(inter, interface)) return true;

            return false;
        }

        fn verifyKind(comptime kind: []const u8) void {
            if (!@hasField(GeneratedSets, kind))
                @compileError("Hook kind '" ++ kind ++ "' does not exist");
        }
    };
}

pub const EditorHooks = GenerateHooks(EditorHooksInterfaces);
pub const EditorHooksInterfaces = struct {
    buffer_created: BufferCreated,
    after_insert: Change,
    after_delete: Change,

    const Change = struct {
        ptr: *anyopaque,
        call_fn: *const fn (ptr: *anyopaque, buffer: *Buffer, bhandle: ?BufferHandle, change: Buffer.Change) void,
        pub fn call(self: Change, buffer: *Buffer, bhandle: ?BufferHandle, change: Buffer.Change) void {
            self.call_fn(self.ptr, buffer, bhandle, change);
        }
    };

    const BufferCreated = struct {
        ptr: *anyopaque,
        call_fn: *const fn (ptr: *anyopaque, buffer: *Buffer, bhandle: BufferHandle) void,
        pub fn call(self: BufferCreated, buffer: *Buffer, bhandle: BufferHandle) void {
            self.call_fn(self.ptr, buffer, bhandle);
        }
    };
};
