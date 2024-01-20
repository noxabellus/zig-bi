pub const std = @import("std");
pub const val = @import("value");

pub const Code = struct {
    allocator: ?std.mem.Allocator,
    instrs: []const u8,

    pub fn init(allocator: std.mem.Allocator, instrs: []const u8) Code {
        return Code { .allocator = allocator, .instrs = instrs };
    }

    pub fn deinit(self: Code) void {
        if (self.allocator) |al| {
            al.free(self.instrs);
        }
    }
};

pub const Instruction = enum(u8) {
    Unreachable = 0xFF,
    NoOp = 0x00,

    Push,
    Pop,
    Swap,
    Duplicate,

    GetLocal,
    SetLocal,

    HandlerPush,
    HandlerPop,

    Call, Return,
    Prompt, Continue,
    Jump, JumpIf,

    Eq, Ne, Lt, Le, Gt, Ge,
    Add, Sub, Mul, Div, Mod, Pow, Abs, Neg,
    LAnd, LOr, LNot,
    BAnd, BOr, BXor, BNot, LShift, RShift,


    pub fn format(self: Instruction, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = fmt;
        _ = options;
        return writer.print("{s}", .{@tagName(self)});
    }

    pub fn encode(self: Instruction, encoder: *Encoder) !void {
        return encoder.pushInt(@intFromEnum(self));
    }

    pub fn disasm(self: Instruction, disassembler: *const Disassembler, ip: *u64, writer: anytype) !void {
        try writer.print("{any}", .{self});

        switch (self) {
            .Unreachable, .NoOp,
            .Eq, .Ne, .Lt, .Le, .Gt, .Ge,
            .Add, .Sub, .Mul, .Div, .Mod, .Pow, .Abs, .Neg,
            .LAnd, .LOr, .LNot,
            .BAnd, .BOr, .BXor, .BNot, .LShift, .RShift,
            => {},

            .Push => {
                const imm = std.mem.readIntSliceLittle(u64, try disassembler.readBytes(ip, 8));
                try writer.print(" {}", .{imm});
            },

            .Pop => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .Swap => {
                try writer.print(" {} {}", .{try disassembler.readByte(ip), try disassembler.readByte(ip)});
            },

            .Duplicate => {
                try writer.print(" {} {}", .{try disassembler.readByte(ip), try disassembler.readByte(ip)});
            },

            .GetLocal => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .SetLocal => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .HandlerPush => {
                const imm = std.mem.readIntSliceLittle(u64, try disassembler.readBytes(ip, 8));
                try writer.print(" {}", .{imm});
            },

            .HandlerPop => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .Call => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .Return => {
                try writer.print("{s}", .{if (try disassembler.readByte(ip) != 0) "+" else "-"});
            },

            .Prompt => {
                try writer.print(" {}", .{try disassembler.readByte(ip)});
            },

            .Continue => {
                try writer.print("{s}", .{if (try disassembler.readByte(ip) != 0) "+" else "-"});
            },

            .Jump => {
                const imm = std.mem.readIntSliceLittle(u64, try disassembler.readBytes(ip, 8));
                try writer.print(" {}", .{imm});
            },

            .JumpIf => {
                const imm = std.mem.readIntSliceLittle(u64, try disassembler.readBytes(ip, 8));
                try writer.print(" {}", .{imm});
            },
        }

        try writer.writeByte('\n');
    }
};

const EncodeError = error{
    TypeError,
};

pub const Encoder = struct {
    data: std.ArrayList(u8),

    pub fn init(allocator: std.mem.Allocator) Encoder {
        return Encoder {
            .data = std.ArrayList(u8).init(allocator),
        };
    }

    pub fn deinit(self: *Encoder) void {
        self.data.deinit();
    }

    pub fn toOwnedSlice(self: Encoder) ![]u8 {
        var out = self;
        return out.data.toOwnedSlice();
    }

    pub fn finalize(self: Encoder) !Code {
        return Code.init(self.data.allocator, try self.toOwnedSlice());
    }

    pub fn pushInt(self: *Encoder, i: anytype) !void {
        try self.data.writer().writeIntLittle(@TypeOf(i), i);
    }

    pub fn encode(self: *Encoder, arg: anytype) !void {
        if (comptime std.meta.trait.hasFn("encode")(@TypeOf(arg))) {
            try arg.encode(self);
        } else {
            try switch (@TypeOf(arg)) {
                bool => self.pushInt(@intFromBool(arg)),

                u8, u16, u32, u64,
                i8, i16, i32, i64,
                => self.pushInt(arg),

                else => return EncodeError.TypeError,
            };
        }
    }
};

pub const Disassembler = struct {
    instrs: []const u8,

    pub fn init(instrs: []const u8) Disassembler {
        return Disassembler {
            .instrs = instrs,
        };
    }

    pub fn readByte(self: *const Disassembler, ip: *u64) !u8 {
        var byte = self.instrs[ip.*];
        ip.* += 1;
        return byte;
    }

    pub fn readBytes(self: *const Disassembler, ip: *u64, len: usize) ![]const u8 {
        var bytes = self.instrs[ip.*..ip.* + len];
        ip.* += len;
        return bytes;
    }

    pub fn disasmInstr(self: *const Disassembler, ip: *u64, writer: anytype) !void {
        var instr: Instruction = @enumFromInt(try self.readByte(ip));
        return instr.disasm(self, ip, writer);
    }

    pub fn disasm(self: *const Disassembler, writer: anytype) !void {
        var ip: u64 = 0;
        while (ip < self.instrs.len) {
            try self.disasmInstr(&ip, writer);
        }
    }

    pub fn format(self: *const Disassembler, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        return self.disasm(writer);
    }
};
