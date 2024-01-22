const std = @import("std");
const val = @import("value");
const Type = val.Type;
const Value = val.Value;
const instr = @import("instruction");

pub const Frame = struct {
    function: Type.Function,
    ip: u64,
    stack_base: u64,
    arity: u8,
};

pub const Trap = enum(u8) {
    TypeError,
    ArityError,
    StackOverflow,
    StackUnderflow,
    OutOfMemory,
    HostError,
    LocalOutOfBounds,
    IpOutOfBounds,
    InvalidBytecode,
    NoFrame,
    Unreachable,
};

pub const Fiber = struct {
    const Self = @This();
    var StackCapacity: u64 = 131072;    // ~1mb
    var CallstackCapacity: u64 = 32768; // ~1mb
    var EvidenceCapacity: u64 = 65536;  // ~1mb


    allocator: std.mem.Allocator,
    stack: std.ArrayList(Value),
    callstack: std.ArrayList(Frame),
    evidence: std.ArrayList(Type.Handler),
    trap: ?struct{Trap, []const u8},

    pub fn init(allocator: std.mem.Allocator) !Self {
        var out = Self {
            .allocator = allocator,
            .stack = try std.ArrayList(Value).initCapacity(allocator, Self.StackCapacity),
            .callstack = try std.ArrayList(Frame).initCapacity(allocator, Self.CallstackCapacity),
            .evidence = try std.ArrayList(Type.Handler).initCapacity(allocator, Self.EvidenceCapacity),
            .trap = null,
        };

        return out;
    }

    pub fn deinit(self: Self) void {
        self.stack.deinit();
        self.callstack.deinit();
        self.evidence.deinit();
    }

    pub fn springTrap(self: *Self, trap: Trap, comptime message: []const u8) !void {
        self.trap = .{trap, message};
        return error.Trap;
    }

    pub fn springTrapT(self: *Self, comptime T: type, trap: Trap, comptime message: []const u8) !T {
        self.trap = .{trap, message};
        return error.Trap;
    }

    pub fn assert(self: *Self, condition: bool, trap: Trap, comptime message: []const u8) !void {
        if (!condition) {
            return self.springTrap(trap, message);
        }
    }

    pub fn push(self: *Self, value: Value, comptime location: []const u8) !void {
        try self.assert(self.stack.items.len < self.stack.capacity, .StackOverflow, "stack overflow in " ++ location);

        return self.stack.appendAssumeCapacity(value);
    }

    pub fn pop(self: *Self, n: u8, comptime location: []const u8) !void {
        try self.assert(self.stackDepth() >= n, .StackUnderflow, "stack underflow in " ++ location);

        return self.stack.shrinkRetainingCapacity(self.stack.items.len - n);
    }

    pub fn pop1(self: *Self, comptime location: []const u8) !Value {
        try self.assert(self.stackDepth() >= 1, .StackUnderflow, "stack underflow in " ++ location);

        return self.stack.pop();
    }

    pub fn duplicate(self: *Self, offset: u8, count: u8, comptime location: []const u8) !void {
        try self.assert(self.stackDepth() >= offset + count, .StackUnderflow, "stack underflow in " ++ location);
        try self.assert(self.stack.items.len + count <= self.stack.capacity, .StackOverflow, "stack overflow in " ++ location);

        const src = self.stack.items[self.stack.items.len - (offset + count)..self.stack.items.len - offset];
        return self.stack.appendSliceAssumeCapacity(src);
    }

    pub fn swap(self: *Self, offset: u8, count: u8, comptime location: []const u8) !void {
        try self.assert(self.stackDepth() >= offset + count, .StackUnderflow, "stack underflow in " ++ location);

        const state = struct {
            threadlocal var tmp: [256]Value = undefined;
        };

        const src = self.stack.items[self.stack.items.len - (offset + count)..self.stack.items.len - offset];
        const swapped = self.stack.items[self.stack.items.len - offset..self.stack.items.len];
        const dest = self.stack.items[self.stack.items.len - count..self.stack.items.len];

        std.mem.copy(Value, state.tmp[0..], src);
        std.mem.copy(Value, src, swapped);
        std.mem.copy(Value, dest, state.tmp[0..src.len]);
    }

    pub fn dumpStack(self: *Self, writer: anytype) !void {
        try writer.print("stack:\n", .{});
        for (self.stack.items, 0..) |value, index| {
            try writer.print("{}: {}\n", .{index, value});
        }
    }

    pub fn stackBase(self: *Self) u64 {
        if (self.currentFrame()) |frame| {
            return frame.stack_base;
        } else {
            return 0;
        }
    }

    pub fn stackDepth(self: *Self) u64 {
        return self.stack.items.len - self.stackBase();
    }

    pub fn localDepth(self: *Self) u64 {
        if (self.currentFrame()) |frame| {
            return frame.function.num_locals;
        } else {
            return 0;
        }
    }

    pub fn currentArity(self: *Self) u8 {
        if (self.currentFrame()) |frame| {
            return frame.arity;
        } else {
            return 0;
        }
    }

    pub fn currentFrame(self: *Self) ?Frame {
        return self.callstack.getLastOrNull();
    }

    pub fn pushFrame(self: *Self, arity: u8, comptime location: []const u8) !void {
        try self.assert(self.callstack.items.len < self.callstack.capacity, .StackOverflow, "callstack overflow in " ++ location);
        try self.assert(self.stackDepth() >= arity + 1, .StackUnderflow, "stack underflow in " ++ location);

        const function = try self.stack.items[self.stack.items.len - (arity + 1)].toNativeChecked(Type.Function);
        try self.assert(self.stack.items.len + function.num_locals <= self.stack.capacity, .StackOverflow, "stack overflow in " ++ location);

        self.stack.items[self.stack.items.len - (arity + 1)] = Value.Nil;

        for (0..function.num_locals) |_| {
            self.stack.appendAssumeCapacity(Value.Nil);
        }

        const frame = Frame {
            .function = function,
            .ip = 0,
            .stack_base = self.stack.items.len,
            .arity = arity,
        };

        return self.callstack.appendAssumeCapacity(frame);
    }

    pub fn popFrame(self: *Self) !Frame {
        try self.assert(self.callstack.items.len > 0, .HostError, "callstack underflow");

        const frame = self.callstack.pop();

        self.stack.shrinkRetainingCapacity(frame.stack_base - (frame.function.num_locals + frame.arity + 1));

        return frame;
    }

    pub fn getParam(self: *Self, index: u8, comptime location: []const u8) !Value {
        const frame =
            if (self.currentFrame()) |frame| frame
            else return self.springTrapT(Value, .HostError, "no frame for get param in " ++ location);

        try self.assert(index < frame.arity, .LocalOutOfBounds, "get param index out of bounds in " ++ location);

        return self.stack.items[frame.stack_base - (frame.function.num_locals + frame.arity) + index];
    }

    pub fn setParam(self: *Self, index: u8, value: Value, comptime location: []const u8) !void {
        const frame =
            if (self.currentFrame()) |frame| frame
            else return self.springTrap(.HostError, "no frame for set param in " ++ location);

        try self.assert(index < frame.arity, .LocalOutOfBounds, "set param index out of bounds in " ++ location);

        self.stack.items[frame.stack_base - (frame.function.num_locals + frame.arity) + index] = value;
    }

    pub fn getLocal(self: *Self, index: u8, comptime location: []const u8) !Value {
        const frame =
            if (self.currentFrame()) |frame| frame
            else return self.springTrapT(Value, .HostError, "no frame for get local in " ++ location);

        try self.assert(index < frame.function.num_locals, .LocalOutOfBounds, "get local index out of bounds in " ++ location);

        return self.stack.items[frame.stack_base - frame.function.num_locals + index];
    }

    pub fn setLocal(self: *Self, index: u8, value: Value, comptime location: []const u8) !void {
        const frame =
            if (self.currentFrame()) |frame| frame
            else return self.springTrap(.HostError, "no frame for set local in " ++ location);

        try self.assert(index < frame.function.num_locals, .LocalOutOfBounds, "set local index out of bounds in " ++ location);

        self.stack.items[frame.stack_base - frame.function.num_locals + index] = value;
    }

    pub fn insertHandler(self: *Self, index: u8, handler: Type.Handler, comptime location: []const u8) !void {
        try self.assert(self.evidence.items.len < self.evidence.capacity, .StackOverflow, "evidence overflow in " ++ location);

        return self.evidence.insertAssumeCapacity(index, handler);
    }

    pub fn removeHandler(self: *Self, index: u8, comptime location: []const u8) !Type.Handler {
        try self.assert(index < self.evidence.items.len, .LocalOutOfBounds, "remove handler index out of bounds in " ++ location);

        return self.evidence.orderedRemove(index);
    }
};
