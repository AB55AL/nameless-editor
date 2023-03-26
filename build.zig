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

pub fn coreModule(bob: *Builder, deps: []const std.build.ModuleDependency) *Module {
    return bob.createModule(.{ .source_file = .{ .path = comptime thisDir() ++ "/src/core.zig" }, .dependencies = deps });
}

pub fn buildEditor(bob: *Builder, input_layer_module: *Module, user_module: ?*Module) void {
    var mecha_module = bob.createModule(.{ .source_file = .{ .path = "libs/mecha/mecha.zig" } });
    var freetype_module = freetype.module(bob);

    var gui_module = bob.createModule(.{ .source_file = .{ .path = "libs/gui/src/api.zig" }, .dependencies = &.{
        .{ .name = "tinyvg", .module = bob.createModule(.{ .source_file = .{ .path = "libs/gui/libs/tinyvg/src/lib/tinyvg.zig" } }) },
        .{ .name = "freetype", .module = freetype_module },
    } });

    var core_module = coreModule(bob, &.{
        .{ .name = "mecha", .module = mecha_module },
        .{ .name = "gui", .module = gui_module },
    });

    input_layer_module.dependencies.putNoClobber("core", core_module) catch unreachable;

    const exe = bob.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = comptime thisDir() ++ "/src/main.zig" },
        .optimize = .Debug,
    });
    exe.linkLibC();

    exe.addModule("freetype", freetype_module);
    exe.addModule("mecha", mecha_module);
    exe.addModule("core", core_module);
    exe.addModule("gui", gui_module);
    exe.addModule("input_layer", input_layer_module);

    exe.linkSystemLibrary("SDL2");

    var options = bob.addOptions();
    exe.addOptions("options", options);

    if (user_module) |um| {
        um.dependencies.putNoClobber("core", core_module) catch unreachable;
        exe.addModule("user", um);
    }

    const user_config_loaded = if (user_module != null) true else false;
    options.addOption(bool, "user_config_loaded", user_config_loaded);

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
    tests.main_pkg_path = comptime thisDir();

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
