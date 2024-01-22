const std = @import("std");
const instr = @import("instruction");
const val = @import("value");
const Type = val.Type;
const Value = val.Value;
const fib = @import("fiber");
const Fiber = fib.Fiber;
const interp = @import("interpreter");

pub fn tryCreateObj(al: std.mem.Allocator, comptime T: type) !*T {
    const obj = try al.create(T);
    obj.* = try T.init(al);
    return obj;
}

pub fn createObj(al: std.mem.Allocator, comptime T: type) !*T {
    const obj = try al.create(T);
    obj.* = T.init(al);
    return obj;
}

pub fn destroyObj(obj: anytype) void {
    const al = obj.allocator;
    obj.deinit();
    al.destroy(obj);
}

pub fn main() !void {
    const al = std.heap.page_allocator;
    const stdout = std.io.getStdIn().writer();

    const fi = try tryCreateObj(al, Fiber);
    defer destroyObj(fi);

    try fi.push(Value.fromNative(@as(Type.SInt, 1)), "main.push");
    try fi.push(Value.fromNative(@as(Type.SInt, 2)), "main.push");
    try fi.push(Value.fromNative(@as(Type.SInt, 3)), "main.push");
    try fi.push(Value.fromNative(@as(Type.SInt, 4)), "main.push");
    try fi.push(Value.fromNative(@as(Type.SInt, 5)), "main.push");
    try fi.dumpStack(stdout);
    try fi.duplicate(1, 2, "main.duplicate");
    try fi.dumpStack(stdout);
    try fi.swap(2, 2, "main.swap");
    try fi.dumpStack(stdout);
    try fi.pop(2, "main.pop");
    try fi.dumpStack(stdout);



    const sp = try createObj(al, Type.underlying(Type.String));
    defer destroyObj(sp);

    try sp.appendSlice("test");

    const vs = Value.fromNative(sp);
    try stdout.print("{s}\n", .{(try vs.toNativeChecked(Type.String)).items});

    const vi = Value.fromNative(@as(Type.SInt, 100));
    try stdout.print("{}\n", .{try vi.toNativeChecked(Type.SInt)});

    const vf = Value.fromNative(@as(Type.Float, 1.1));
    try stdout.print("{}\n", .{try vf.toNativeChecked(Type.Float)});

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

    const code = try e.finalize();
    defer code.deinit();

    try fi.push(Value.fromNative(&Type.FunctionBody {
        .code = code,
        .num_locals = 0
    }), "main.push");
    try fi.push(Value.fromNative(@as(Type.SInt, 1)), "main.push");
    try fi.pushFrame(1, "main.pushFrame");

    interp.step(fi) catch
        if (fi.trap) |trap| {
            try stdout.print("Trap {s} sprung with \"{s}\"\n", .{@tagName(trap[0]), trap[1]});
        } else {
            try stdout.print("Error with no trap?\n", .{});
        };


    // const disasm = instr.Disassembler.init(code.instrs);
    // try stdout.print("Disassembly:\n{}", .{disasm});
}
