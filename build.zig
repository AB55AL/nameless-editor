const Builder = @import("std").build.Builder;
const Source = @import("std").build.FileSource;
const std = @import("std");
const print = std.debug.print;
const Module = std.build.Module;
const concat = std.mem.concat;

const zgui = @import("libs/imgui/build.zig");
const glfw = @import("libs/mach-glfw/build.zig");
const GitRepoStep = @import("GitRepoStep.zig");

pub const standard_input_layer_root_path = thisDir() ++ "/src/input-layers/standard-input-layer/src/main.zig";
pub const vim_like_input_layer_root_path = thisDir() ++ "/src/input-layers/vim-like/src/context.zig";

pub const defualt_ts_repos = [_]TSParserRepo{ tree_sitter_zig, tree_sitter_c };

pub const TSParserRepo = struct {
    url: []const u8,
    lang_name: []const u8,
    dir_name: []const u8,
    branch: ?[]const u8 = null,
    sha: []const u8,
};

const tree_sitter_zig = TSParserRepo{
    .url = "https://github.com/maxxnino/tree-sitter-zig.git",
    .lang_name = "zig",
    .dir_name = "tree-sitter-zig",
    .sha = "0d08703e4c3f426ec61695d7617415fff97029bd",
};

const tree_sitter_c = TSParserRepo{
    .url = "https://github.com/tree-sitter/tree-sitter-c.git",
    .lang_name = "c",
    .dir_name = "tree-sitter-c",
    .sha = "735716c926837d9e39e4effb3fdc28cee81a7e5e",
};

const generated_dir = thisDir() ++ "/generated";
const ts_parsers_dir = generated_dir ++ "/tree-sitter-parsers";
const src_path = thisDir() ++ "/src";

fn thisDir() []const u8 {
    return std.fs.path.dirname(@src().file) orelse ".";
}

pub fn coreModule(bob: *Builder, deps: []const std.build.ModuleDependency) *Module {
    return bob.createModule(.{ .source_file = .{ .path = comptime thisDir() ++ "/src/core.zig" }, .dependencies = deps });
}

pub fn buildEditor(bob: *Builder, input_layer_root_path: []const u8, user_module: ?*Module, ts_parsers: []const TSParserRepo) void {
    const target = bob.standardTargetOptions(.{});
    const optimize = bob.standardOptimizeOption(.{});

    var mecha_module = bob.createModule(.{ .source_file = .{ .path = comptime thisDir() ++ "/libs/mecha/mecha.zig" } });
    var glfw_module = glfw.module(bob);
    var core_module = coreModule(bob, &.{.{ .name = "mecha", .module = mecha_module }});
    var input_layer_module = bob.createModule(.{ .source_file = .{ .path = input_layer_root_path } });

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
    if (user_module) |um| {
        um.dependencies.putNoClobber("core", core_module) catch unreachable;
        um.dependencies.putNoClobber("imgui", imgui.zgui) catch unreachable;
        exe.addModule("user", um);
    }

    var options = bob.addOptions();
    exe.addOptions("options", options);

    exe.linkSystemLibrary("tree-sitter");
    for (ts_parsers) |parser_repo| {
        const path = std.fs.path.join(bob.allocator, &.{ ts_parsers_dir, parser_repo.dir_name }) catch unreachable;
        const repo = GitRepoStep.create(bob, .{
            .url = parser_repo.url,
            .sha = parser_repo.sha,
            .path = path,
        });
        repo.fetch_enabled = true;
        exe.step.dependOn(&repo.step);

        const parser_path = std.fs.path.join(bob.allocator, &.{ path, "src", "parser.c" }) catch unreachable;
        exe.addCSourceFile(parser_path, &.{});
    }

    generateTSLanguageFile(bob, ts_parsers) catch unreachable;

    options.addOption(bool, "user_config_loaded", user_module != null);

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
        .optimize = optimize,
    });
    tests.main_pkg_path = comptime thisDir();

    const test_step = bob.step("test", "Run tests");
    test_step.dependOn(&tests.step);
}

fn generateTSLanguageFile(bob: *Builder, ts_parsers: []const TSParserRepo) !void {
    var file = try std.fs.createFileAbsolute(src_path ++ "/tree_sitter_languages.zig", .{});
    defer file.close();

    const file_top =
        \\const std = @import("std");
        \\const ts = @cImport(@cInclude("tree_sitter/api.h"));
        \\const HashMap = std.StringHashMap(*ts.TSLanguage);
        \\pub fn init(allocator: std.mem.Allocator) !HashMap {
        \\var ts_langs = HashMap.init(allocator);
        \\
    ;

    var content = std.ArrayList(u8).init(bob.allocator);
    try content.appendSlice(file_top);

    // language hashmap init
    for (ts_parsers) |parser_repo| {
        const fmt =
            \\try ts_langs.put( "{s}",tree_sitter_{s}() );
            \\
        ;
        const line = try std.fmt.allocPrint(bob.allocator, fmt, .{ parser_repo.lang_name, parser_repo.lang_name });

        try content.appendSlice(line);
    }

    const return_string =
        \\
        \\return ts_langs;
        \\}
        \\
    ;
    try content.appendSlice(return_string);

    // function declaration
    for (ts_parsers) |parser_repo| {
        const fmt =
            \\extern fn tree_sitter_{s}() *ts.TSLanguage;
            \\
        ;
        const line = try std.fmt.allocPrint(bob.allocator, fmt, .{parser_repo.lang_name});
        try content.appendSlice(line);
    }

    _ = try file.write(content.items);
}

pub fn build(bob: *Builder) void {
    buildEditor(bob, vim_like_input_layer_root_path, null, &defualt_ts_repos);
}
