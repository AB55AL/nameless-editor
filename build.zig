const Builder = @import("std").build.Builder;
const Source = @import("std").build.FileSource;
const std = @import("std");

const glfw = @import("libs/mach-glfw/build.zig");
const freetype = @import("libs/mach-freetype/build.zig");

pub fn build(b: *Builder) void {
    b.setPreferredReleaseMode(std.builtin.Mode.Debug);

    const exe = b.addExecutable("main", "src/main.zig");
    exe.linkLibC();
    exe.addCSourceFile("src/ui/glad/glad.c", &[_][]const u8{
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

    glfw.link(b, exe, .{});
    freetype.link(b, exe, .{});
    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const tests = b.addTest("tests/buffer.zig");
    tests.setBuildMode(std.builtin.Mode.ReleaseSafe);
    tests.addPackagePath("core", "src/core.zig");

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&tests.step);
}
