const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) !void {
    const exe =
        b.addExecutable(.{
            .name = "main",
            .root_source_file = .{ .path = "src/main.zig" },
        });

    const fiber =
        b.addModule("fiber", .{
            .source_file = .{ .path = "src/fiber.zig" }
        });

    const value =
        b.addModule("value", .{
            .source_file = .{ .path = "src/value.zig" },
            .dependencies = &.{
                .{ .name = "fiber", .module = fiber },
            },
        });

    const instruction =
        b.addModule("instruction", .{
            .source_file = .{ .path = "src/instruction.zig" },
            .dependencies = &.{
                .{ .name = "value", .module = value },
            },
        });

    try value.dependencies.put("instruction", instruction);

    try fiber.dependencies.put("instruction", instruction);
    try fiber.dependencies.put("value", value);

    exe.addModule("instruction", instruction);
    exe.addModule("fiber", fiber);
    exe.addModule("value", value);
    b.installArtifact(exe);
}
