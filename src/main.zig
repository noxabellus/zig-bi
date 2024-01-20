const std = @import("std");
const instr = @import("instruction");
const val = @import("value");
const fib = @import("fiber");

pub fn main() !void {
    const stdout = std.io.getStdIn().writer();

    const al = std.heap.page_allocator;
    const sp: val.Type.String = try al.create(std.ArrayList(u8));
    sp.* = std.ArrayList(u8).init(al);
    try sp.appendSlice("test");
    var s = val.Value.from_native(sp);
    try stdout.print("{s}\n", .{(try s.to_native_cc(val.Type.String)).items});

    const si = val.Value.from_native(@as(val.Type.SInt, 100));
    try stdout.print("{}\n", .{try si.to_native_cc(val.Type.SInt)});

    const sf = val.Value.from_native(@as(val.Type.Float, 1.1));
    try stdout.print("{}\n", .{try sf.to_native_cc(val.Type.Float)});

    var e = instr.Encoder.init(std.heap.page_allocator);

    try e.encode(instr.Instruction.Push);
    try e.encode(@as(u64, 1));
    try e.encode(instr.Instruction.Push);
    try e.encode(@as(u64, 2));
    try e.encode(instr.Instruction.Swap);
    try e.encode(@as(u8, 1));
    try e.encode(@as(u8, 1));
    try e.encode(instr.Instruction.Call);
    try e.encode(@as(u8, 2));
    try e.encode(instr.Instruction.Return);
    try e.encode(true);

    var instrs = try e.to_owned_slice();

    var disasm = instr.Disassembler.init(instrs);

    try stdout.print("Disassembly:\n{}", .{disasm});
}
