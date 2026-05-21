const std = @import("std");

pub fn build(b: *std.Build) void {
    // Set targeting to default to WebAssembly Freestanding architecture
    const target = b.standardTargetOptions(.{
        .default_target = .{
            .cpu_arch = .wasm32,
            .os_tag = .freestanding,
        },
    });

    const optimize = b.standardOptimizeOption(.{});

    // Build the executable binary
    const exe = b.addExecutable(.{
        .name = "plasma",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/bridge.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    // Expose WebAssembly exports dynamically
    exe.rdynamic = true;
    
    // Wasm freestanding apps don't have traditional main entries
    exe.entry = .disabled;

    // Redirect install target directly to the /web directory to match Spacestory's architecture
    const install_wasm = b.addInstallArtifact(exe, .{
        .dest_dir = .{ .override = .{ .custom = "../web" } },
    });
    
    b.getInstallStep().dependOn(&install_wasm.step);
}
