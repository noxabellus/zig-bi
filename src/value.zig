const std = @import("std");
const fib = @import("fiber");
const Fiber = fib.Fiber;

pub const Tag = enum(u16) {
    const Self = @This();

    Nil = 0xFFFF,
    Pointer = 0x0000,

    Bool,
    Float,
    SInt,
    UInt,
    Symbol,

    String,
    Array,
    Map,
    Set,

    Function,
    ForeignFunction,

    pub fn encoded(self: Self) u64 {
        return @as(u64, @intFromEnum(self)) << 48;
    }

    pub fn decode_bits(bits: u64) u16 {
        return @intCast(bits >> 48);
    }

    pub fn decode(bits: u64) !Self {
        switch (Self.decode_bits(bits)) {
            @intFromEnum(Tag.Nil) => return Tag.Nil,
            @intFromEnum(Tag.Pointer) => return Tag.Pointer,
            @intFromEnum(Tag.Bool) => return Tag.Bool,
            @intFromEnum(Tag.Float) => return Tag.Float,
            @intFromEnum(Tag.SInt) => return Tag.SInt,
            @intFromEnum(Tag.UInt) => return Tag.UInt,
            @intFromEnum(Tag.String) => return Tag.String,
            @intFromEnum(Tag.Array) => return Tag.Array,
            @intFromEnum(Tag.Map) => return Tag.Map,
            @intFromEnum(Tag.Set) => return Tag.Set,
            @intFromEnum(Tag.Symbol) => return Tag.Symbol,
            @intFromEnum(Tag.Function) => return Tag.Function,
            @intFromEnum(Tag.ForeignFunction) => return Tag.ForeignFunction,
            else => {
                // try std.io.getStdErr().writer().print("ValueError: invalid tag {}\n", .{@as(u16, @intCast(bits >> 48))});
                return ValueError.InvalidTag;
            },
        }
    }

    pub fn from_type(comptime T: type) Self {
        switch (T) {
            Type.Nil => return Tag.Nil,
            Type.Pointer => return Tag.Pointer,
            Type.Bool => return Tag.Bool,
            Type.Float => return Tag.Float,
            Type.SInt => return Tag.SInt,
            Type.UInt => return Tag.UInt,
            Type.String => return Tag.String,
            Type.Array => return Tag.Array,
            Type.Map => return Tag.Map,
            Type.Set => return Tag.Set,
            Type.Symbol => return Tag.Symbol,
            Type.Function => return Tag.Function,
            Type.ForeignFunction => return Tag.ForeignFunction,
            else => {
                @compileLog("comptime T = ", T);
                @compileError("invalid type for Tag.from_type");
            },
        }
    }
};

pub const ValueError = error {
    TypeError,
    InvalidTag,
};

pub const ValueRepr = u64;

pub const Type = struct {
    pub const Nil = void;
    pub const Pointer = *opaque{};
    pub const Bool = bool;
    pub const Float = f32;
    pub const SInt = i32;
    pub const UInt = u32;
    pub const String = *std.ArrayList(u8);
    pub const Array = *std.ArrayList(Value);
    pub const Map = *std.AutoHashMap(Value, Value);
    pub const Set = *std.AutoHashMap(Value, Nil);

    pub const Symbol = enum(u48) {
        _,
    };

    pub const Function = struct {

    };

    pub const ForeignFunction = fn (fiber: *Fiber, args: []Value) Value;

    pub fn from_tag(comptime tag: Tag) type {
        switch (tag) {
            Tag.Nil => return Type.Nil,
            Tag.Pointer => return Type.Pointer,
            Tag.Bool => return Type.Bool,
            Tag.Float => return Type.Float,
            Tag.SInt => return Type.SInt,
            Tag.UInt => return Type.UInt,
            Tag.String => return Type.String,
            Tag.Array => return Type.Array,
            Tag.Map => return Type.Map,
            Tag.Set => return Type.Set,
            Tag.Symbol => return Type.Symbol,
            Tag.Function => return Type.Function,
            Tag.ForeignFunction => return Type.ForeignFunction,
            else => @compileError("invalid tag for Type.from_tag"),
        }
    }

    pub fn encode(v: anytype) ValueRepr {
        switch (@TypeOf(v)) {
            Type.Nil => return 0,
            Type.Pointer => return @intFromPtr(v),
            Type.Bool => return @intFromBool(v),
            Type.Float => return @intCast(@as(u32, @bitCast(v))),
            Type.SInt => return @intCast(@as(u32, @bitCast(v))),
            Type.UInt => return @intCast(v),
            Type.String => return @intFromPtr(v),
            Type.Array => return @intFromPtr(v),
            Type.Map => return @intFromPtr(v),
            Type.Set => return @intFromPtr(v),
            Type.Symbol => return @intCast(@intFromEnum(v)),
            Type.Function => return @intFromPtr(v),
            Type.ForeignFunction => return @intFromPtr(v),
            else => @compileError("invalid type for Type.encode"),
        }
    }

    pub fn decode(comptime T: type, bits: u64) T {
        switch (T) {
            Type.Nil => return 0,
            Type.Pointer => return @ptrFromInt(bits),
            Type.Bool => return bits != 0,
            Type.Float => return @bitCast(@as(u32, @intCast(bits))),
            Type.SInt => return @intCast(bits),
            Type.UInt => return @intCast(bits),
            Type.String => return @ptrFromInt(bits),
            Type.Array => return @ptrFromInt(bits),
            Type.Map => return @ptrFromInt(bits),
            Type.Set => return @ptrFromInt(bits),
            Type.Symbol => return @enumFromInt(@as(u48, @intCast(bits))),
            Type.Function => return @ptrFromInt(bits),
            Type.ForeignFunction => return @ptrFromInt(bits),
            else => @compileError("invalid type for Type.decode"),
        }
    }
};

pub const Value = enum(ValueRepr) {
    _,

    const Self = @This();

    pub const Nil: Self = @enumFromInt(@as(u64, @intFromEnum(Tag.Nil)) << 48);

    pub const TagMask: ValueRepr  = 0b1111111111111111000000000000000000000000000000000000000000000000;
    pub const DataMask: ValueRepr = 0b0000000000000000111111111111111111111111111111111111111111111111;


    pub fn is_tag(self: Self, tag: Tag) bool {
        return Tag.decode_bits(@intFromEnum(self)) == @intFromEnum(tag);
    }

    pub fn is_type(self: Self, comptime T: type) bool {
        return self.is_tag(Tag.from_type(T));
    }


    pub fn is_nil(self: Self) bool {
        return self.is_tag(.Nil);
    }


    pub fn from_native(v: anytype) Self {
        return @enumFromInt(Tag.from_type(@TypeOf(v)).encoded() | Type.encode(v));
    }

    pub fn to_native_cc(self: Self, comptime T: type) !T {
        if (self.is_type(T)) {
            return self.to_native_uc(T);
        } else {
            // try std.io.getStdErr().writer().print("ValueError: expected type {}, got {}\n", .{T, try Tag.decode(@intFromEnum(self))});
            return ValueError.TypeError;
        }
    }

    pub fn to_native_uc(self: Self, comptime T: type) T {
        return Type.decode(T, @intFromEnum(self) & Self.DataMask);
    }
};
