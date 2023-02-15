const Builder = @import("std").build.Builder;
const Source = @import("std").build.FileSource;
const std = @import("std");
const print = std.debug.print;
const Module = std.build.Module;

const glfw = @import("libs/mach-glfw/build.zig");
const freetype = @import("libs/mach-freetype/build.zig");

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn coreModule(bob: *Builder) *Module {
    return bob.createModule(.{ .source_file = .{ .path = comptime thisDir() ++ "/src/core.zig" } });
}

pub fn buildEditor(bob: *Builder, input_layer_module: *Module, user_module: ?*Module) void {
    var core_module = coreModule(bob);
    var glfw_module = glfw.module(bob);
    var freetype_module = freetype.module(bob);

    const exe = bob.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = comptime thisDir() ++ "/src/main.zig" },
        .optimize = .Debug,
    });
    exe.linkLibC();
    exe.addIncludePath(comptime thisDir() ++ "/src/ui/glad/include");
    exe.addCSourceFile(comptime thisDir() ++ "/src/ui/glad/glad.c", &[_][]const u8{});

    exe.addModule("glfw", glfw_module);
    exe.addModule("freetype", freetype_module);

    input_layer_module.dependencies.putNoClobber("core", core_module) catch unreachable;
    input_layer_module.dependencies.putNoClobber("glfw", glfw_module) catch unreachable;
    exe.addModule("input_layer", input_layer_module);

    var options = bob.addOptions();
    exe.addOptions("options", options);

    if (user_module) |um| {
        um.dependencies.putNoClobber("core", core_module) catch unreachable;
        exe.addModule("user", um);
    }

    const user_config_loaded = if (user_module != null) true else false;
    options.addOption(bool, "user_config_loaded", user_config_loaded);

    glfw.link(bob, exe, .{}) catch |err| print("err={}", .{err});
    freetype.link(bob, exe, .{});
    // freetype.link(bob, exe, .{ .harfbuzz = .{} });

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(bob.getInstallStep());

    const run_step = bob.step("run", "Run the editor");
    run_step.dependOn(&run_cmd.step);

    const tests = bob.addTest(.{
        .name = "buffer test",
        .root_source_file = .{ .path = comptime thisDir() ++ "/tests/buffer.zig" },
    });

    tests.addModule("core", core_module);

    const test_step = bob.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}

pub fn build(bob: *Builder) void {
    // const standard_input_layer_root_path = comptime thisDir() ++ "/src/input-layers/standard-input-layer/src/main.zig";
    const standard_input_layer_root_path = comptime thisDir() ++ "/src/input-layers/vim-like/src/main.zig";
    var module = bob.createModule(.{
        .source_file = .{ .path = standard_input_layer_root_path },
    });

    buildEditor(bob, module, null);
}
