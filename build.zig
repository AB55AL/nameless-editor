const Builder = @import("std").build.Builder;
const Source = @import("std").build.FileSource;
const std = @import("std");

const glfw = @import("libs/mach-glfw/build.zig");
const freetype = @import("libs/mach-freetype/build.zig");

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub const core_pkg = std.build.Pkg{
    .name = "core",
    .source = .{ .path = thisDir() ++ "/src/core.zig" },
};

pub fn buildEditor(bob: *Builder, comptime input_layer_path: []const u8) void {
    const exe = bob.addExecutable("main", comptime thisDir() ++ "/src/main.zig");
    exe.setBuildMode(std.builtin.Mode.Debug);
    exe.linkLibC();
    exe.addIncludeDir(comptime thisDir() ++ "/src/ui/glad/include");
    exe.addCSourceFile(comptime thisDir() ++ "/src/ui/glad/glad.c", &[_][]const u8{});

    exe.addPackage(glfw.pkg);
    exe.addPackage(freetype.pkg);
    exe.addPackage(freetype.harfbuzz_pkg);

    exe.addPackage(.{
        .name = "input_layer",
        .source = .{ .path = input_layer_path ++ "/src/main.zig" },
        .dependencies = &.{core_pkg},
    });

    exe.addPackagePath("c_ft_hb", "libs/mach-freetype/src/c.zig");

    glfw.link(bob, exe, .{});
    freetype.link(bob, exe, .{ .harfbuzz = .{} });
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(bob.getInstallStep());

    const run_step = bob.step("run", "Run the editor");
    run_step.dependOn(&run_cmd.step);

    const tests = bob.addTest(comptime thisDir() ++ "/tests/buffer.zig");
    tests.setBuildMode(std.builtin.Mode.Debug);
    tests.addPackagePath("core", comptime thisDir() ++ "/src/core.zig");

    const test_step = bob.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}

pub fn build(bob: *Builder) void {
    const standard_input_layer_path = comptime thisDir() ++ "/input-layers/standard-input-layer";
    buildEditor(bob, standard_input_layer_path);
}
