const Builder = @import("std").build.Builder;
const Source = @import("std").build.FileSource;
const std = @import("std");
const print = std.debug.print;
const Module = std.build.Module;

const zgui = @import("libs/imgui/build.zig");
const glfw = @import("libs/mach-glfw/build.zig");

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn coreModule(bob: *Builder, deps: []const std.build.ModuleDependency) *Module {
    return bob.createModule(.{ .source_file = .{ .path = comptime thisDir() ++ "/src/core.zig" }, .dependencies = deps });
}

pub fn buildEditor(bob: *Builder, input_layer_module: *Module, user_module: ?*Module) void {
    const target = bob.standardTargetOptions(.{});
    const optimize = bob.standardOptimizeOption(.{});

    var mecha_module = bob.createModule(.{ .source_file = .{ .path = "libs/mecha/mecha.zig" } });
    var glfw_module = glfw.module(bob);

    var core_module = coreModule(bob, &.{
        .{ .name = "mecha", .module = mecha_module },
    });

    var imgui = zgui.package(bob, target, optimize, .{ .options = .{ .backend = .glfw_opengl3 } });

    input_layer_module.dependencies.putNoClobber("core", core_module) catch unreachable;
    input_layer_module.dependencies.putNoClobber("imgui", imgui.zgui) catch unreachable;

    const exe = bob.addExecutable(.{
        .name = "main",
        .root_source_file = .{ .path = comptime thisDir() ++ "/src/main.zig" },
        .optimize = optimize,
    });
    exe.linkLibC();

    exe.addModule("mecha", mecha_module);
    exe.addModule("core", core_module);
    exe.addModule("glfw", glfw_module);
    exe.addModule("input_layer", input_layer_module);

    var options = bob.addOptions();
    exe.addOptions("options", options);

    if (user_module) |um| {
        um.dependencies.putNoClobber("core", core_module) catch unreachable;
        exe.addModule("user", um);
    }

    const user_config_loaded = if (user_module != null) true else false;
    options.addOption(bool, "user_config_loaded", user_config_loaded);

    imgui.link(exe);
    glfw.link(bob, exe, .{}) catch unreachable;

    bob.installArtifact(exe);

    const run_cmd = bob.addRunArtifact(exe);
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
