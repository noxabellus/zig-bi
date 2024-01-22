const std = @import("std");
const m_fiber = @import("fiber");
const m_value = @import("value");
const m_instruction = @import("instruction");

const Type  = m_value.Type;
const Value = m_value.Value;
const Fiber = m_fiber.Fiber;
const Code = m_instruction.Code;
const Instruction = m_instruction.Instruction;
const CodeError = m_instruction.CodeError;
const Decoder = m_instruction.Decoder;

pub inline fn step(fiber: *Fiber) !void {
    var frame =
        if (fiber.currentFrame()) |f| f
        else return fiber.springTrap(.NoFrame, "cannot step fiber, no call frame on stack");

    try fiber.assert(frame.ip < frame.function.code.instrs.len, .IpOutOfBounds, "instruction pointer is invalid");

    var decoder = Decoder.init(frame.function.code.instrs, frame.ip);

    const instr =
        decoder.read(Instruction) catch
            return fiber.springTrap(.IpOutOfBounds, "invalid instruction pointer");

    switch (instr) {
        .Push => {
            std.debug.print("push\n", .{});

            const value = decoder.read(Value) catch
                return fiber.springTrap(.InvalidBytecode, "invalid value operand for push");

            try fiber.push(value, "push");
        },

        .Pop => {
            std.debug.print("pop\n", .{});

            const count = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid count operand for pop");

            try fiber.pop(count, "pop");
        },

        .Swap => {
            std.debug.print("swap\n", .{});

            const offset = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid offset operand for swap");

            const count = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid count operand for swap");

            try fiber.swap(offset, count, "swap");
        },

        .Duplicate => {
            std.debug.print("duplicate\n", .{});

            const offset = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid offset operand for duplicate");

            const count = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid count operand for duplicate");

            try fiber.duplicate(offset, count, "duplicate");
        },

        .NumParams => {
            std.debug.print("num params\n", .{});

            const arity = fiber.currentArity();

            try fiber.push(Value.fromNative(@as(Type.UInt, @intCast(arity))), "num params");
        },

        .GetParam => {
            std.debug.print("get param\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for get param");

            const value = try fiber.getParam(index, "get param");

            try fiber.push(value, "get param");
        },

        .SetParam => {
            std.debug.print("set param\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for set param");

            const value = try fiber.pop1("set param");

            try fiber.setParam(index, value, "set param");
        },

        .GetLocal => {
            std.debug.print("get local\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for get local");

            const value = try fiber.getLocal(index, "get local");

            try fiber.push(value, "get local");
        },

        .SetLocal => {
            std.debug.print("set local\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for set local");

            const value = try fiber.pop1("set local");

            try fiber.setLocal(index, value, "set local");
        },

        .InsertHandler => {
            std.debug.print("insert handler\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for insert handler");

            const value = try fiber.pop1("insert handler");

            const handler = value.toNativeChecked(Type.Handler) catch
                return fiber.springTrap(.TypeError, "insert handler expects handler value");

            try fiber.insertHandler(index, handler, "insert handler");
        },

        .RemoveHandler => {
            std.debug.print("remove handler\n", .{});

            const index = decoder.read(u8) catch
                return fiber.springTrap(.InvalidBytecode, "invalid index operand for remove handler");

            const handler = try fiber.removeHandler(index, "remove handler");

            try fiber.push(Value.fromNative(handler), "remove handler");
        },

        else => return fiber.springTrap(.InvalidBytecode, "instruction not yet implemented"),
    }

    frame.ip = decoder.ip;
}

pub fn eval(fiber: *Fiber) !void {
    while (fiber.callstack.len > 0) {
        try step(fiber);
    }
}
