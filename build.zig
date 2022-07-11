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

pub fn buildEditor(b: *Builder, comptime input_layer_path: []const u8) void {
    b.setPreferredReleaseMode(std.builtin.Mode.Debug);

    const exe = b.addExecutable("main", comptime thisDir() ++ "/src/main.zig");
    exe.linkLibC();
    exe.addCSourceFile(comptime thisDir() ++ "/src/ui/glad/glad.c", &[_][]const u8{
        "-lc",
        "-lglfw3",
        "-lGL",
        "-lX11",
        "-lpthread",
        "-lXrandr",
        "-lXi",
        "-ldl",
        "-I/usr/include",
    });
    exe.addPackage(glfw.pkg);
    exe.addPackage(freetype.pkg);

    exe.addPackage(.{
        .name = "input_layer",
        .source = .{ .path = input_layer_path ++ "/src/main.zig" },
        .dependencies = &.{core_pkg},
    });

    glfw.link(b, exe, .{});
    freetype.link(b, exe, .{});
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest(comptime thisDir() ++ "/tests/buffer.zig");
    tests.setBuildMode(std.builtin.Mode.ReleaseSafe);
    tests.addPackagePath("core", comptime thisDir() ++ "/src/core.zig");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}

pub fn build(b: *Builder) void {
    const standard_input_layer_path = comptime thisDir() ++ "/input-layers/standard-input-layer";
    buildEditor(b, standard_input_layer_path);
}
