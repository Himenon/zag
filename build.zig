const std = @import("std");

fn generate_zip_script(b: *std.Build, os: []const u8, arch: []const u8) []const u8 {
    const zip_file_name = std.fmt.allocPrint(b.allocator, "zag-{s}-{s}.zip", .{ os, arch }) catch unreachable;

    return std.fmt.allocPrint(b.allocator,
        \\#!/bin/sh
        \\
        \\mkdir -p artifacts
        \\zip -r {s} ./zig-out/bin/
        \\mv {s} artifacts/
        \\
    , .{ zip_file_name, zip_file_name }) catch unreachable;
}

// この関数は命令型のように見えるが、その役割は、外部のランナーによって実行される
// ビルドグラフを宣言的に構築することである。
pub fn build(b: *std.Build) void {
    // 標準のターゲットオプションを使用すると、`zig build` を実行する際に
    // どのターゲットをビルドするかを選択できる。ここではデフォルト設定を
    // 上書きしないため、あらゆるターゲットを指定でき、デフォルトはネイティブとなる。
    // サポートするターゲットのセットを制限するための他のオプションも利用可能。
    const target = b.standardTargetOptions(.{});

    // 標準の最適化オプションを使用すると、`zig build` を実行する際に
    // Debug、ReleaseSafe、ReleaseFast、ReleaseSmall の中から選択できる。
    // ここでは特定のリリースモードを設定せず、ユーザーが最適化方法を選択できるようにする。
    const optimize = b.standardOptimizeOption(.{});
    const arch = @tagName(target.result.cpu.arch);
    const os = @tagName(target.result.os.tag);
    // @tagNameを利用するとenumがその宣言名になって返ってくる
    std.debug.print("Building for arch: {s}, platform: {s}\n", .{
        @tagName(target.result.cpu.arch),
        @tagName(target.result.os.tag),
    });

    const script_content = generate_zip_script(b, os.arch);

    var file = std.fs.cwd().createFile("./packing.sh", .{ .mode = 0o755 }) catch unreachable;
    defer file.close();
    var writer = file.writer();
    writer.writeAll(script_content) catch {};

    const lib = b.addStaticLibrary(.{
        .name = "zag",
        // この場合、メインのソースファイルは単なるパスだが、より複雑なビルドスクリプトでは
        // 生成されたファイルになることもある。
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    // これは、ユーザーが `zig build` の "install" ステップを実行した際に、
    // 標準のインストール場所にライブラリをインストールする意図を宣言する。
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "zag",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    // これは、ユーザーが `zig build` の "install" ステップを実行した際に、
    // 標準のインストール場所に実行ファイルをインストールする意図を宣言する。
    b.installArtifact(exe);

    // これはビルドグラフ内に Run ステップを *作成* し、
    // それに依存する別のステップが評価されると実行されるようにする。
    // 次の行でその依存関係を確立する。
    const run_cmd = b.addRunArtifact(exe);

    // run ステップが install ステップに依存するようにすることで、
    // 実行ファイルはキャッシュディレクトリ内ではなく、インストールディレクトリから実行される。
    // これは必須ではないが、アプリケーションが他のインストール済みファイルに依存する場合、
    // それらが適切な場所に存在することを保証する。
    run_cmd.step.dependOn(b.getInstallStep());

    // これにより、ビルドコマンド内でアプリケーションに引数を渡せるようになる。
    // 例えば、`zig build run -- arg1 arg2 etc` のように実行できる。
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    // これはビルドステップを作成する。このステップは `zig build --help` メニューに表示され、
    // `zig build run` のように選択できる。
    // これを実行すると、デフォルトの "install" ではなく、`run` ステップが評価される。
    const run_step = b.step("run", "アプリケーションを実行");
    run_step.dependOn(&run_cmd.step);

    // ユニットテスト用のステップを作成する。
    // これはテスト用の実行ファイルをビルドするだけで、実行はしない。
    const lib_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/root.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_lib_unit_tests = b.addRunArtifact(lib_unit_tests);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);

    // 先ほどの `run` ステップの作成と同様に、`test` ステップを `zig build --help`
    // メニューに表示させる。これにより、ユーザーがユニットテストの実行を選択できる。
    const test_step = b.step("test", "ユニットテストを実行");
    test_step.dependOn(&run_lib_unit_tests.step);
    test_step.dependOn(&run_exe_unit_tests.step);
}
