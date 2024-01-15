const std = @import("std");
const StringHashMap = std.StringHashMap;
const Allocator = std.mem.Allocator;
const ESScope = @import("scope.zig").ESScope;

// Dynamic Vars
pub const ESVarType = enum {
  CONST, VAR, LET
};

pub const ESNumber = struct {
  value: f64,

  pub fn toString(self: *const ESNumber) []const u8 {
    var integer: bool = self.value == std.math.round(self.value);
    // TODO: Replace with ArrayList
    var buf: [60]u8 = undefined;

    if (std.math.isNan(self.value)) {
      return "NaN";
    }

    if (std.math.isInf(self.value)) {
      return "Infinity";
    }

    if (integer) {
      const castInt: i64 = @intFromFloat(self.value);
      const slice = std.fmt.bufPrint(buf[0..], "{d}", .{castInt}) catch unreachable;
      return slice;
    } else {
      const castInt: i64 = @intFromFloat(self.value);
      var fpBuf: [80]u8 = undefined;
      var fpSlice = std.fmt.bufPrint(fpBuf[0..], "{:.20}", .{self.value}) catch unreachable;
      const slice = std.fmt.bufPrint(buf[0..], "{d}.{s}", .{castInt, fpSlice[3..fpSlice.len-4]}) catch unreachable;
      return slice;
    }
  }
};

pub const ESObject = struct {
  value: *ESObjectImpl,

  pub fn toString(_: *const ESObject) []const u8 {
    return "{}";
  }
};

pub const ESObjectImpl = struct {
  allocator: *const Allocator,
  properties: StringHashMap(ESType),

  pub fn addProperty(self: *ESObjectImpl, identifier: []const u8, value: ESType) !void {
    try self.properties.put(identifier, value);
  }

  pub fn init(allocator: Allocator) !*ESObjectImpl {
    const object = try allocator.create(ESObjectImpl);
    object.* = .{
      .allocator = &allocator,
      .properties = StringHashMap(ESType).init(allocator),
    };
    return object;
  }

  pub fn deinit(self: *ESObjectImpl) void {
    self.properties.deinit();
  }
};

pub const ESNativeFunction = struct {
  value: usize,

  pub fn call(self: *ESNativeFunction, args: ?[][]const u8) !void {
    const func: *const fn(?[][]const u8) void = @ptrFromInt(self.value);
    func(args);
  }

  pub fn toString(_: ESNativeFunction) []const u8 {
    return "[native function]";
  }
};

pub const ESFunction = struct {
  scope: *ESScope,

  pub fn call(self: *ESFunction, args: ?[][]const u8) anyerror!void {
    try self.scope.exec(args);
  }

  pub fn toString(_: *const ESFunction) []const u8 {
    return "fn";
  }
};

pub const ESString = struct {
  value: []const u8,

  pub fn toString(self: *const ESString) []const u8 {
    return self.value;
  }
};

pub const ESType = union(enum) {
  Number: ESNumber,
  String: ESString,
  Function: ESFunction,
  Undefined: ESUndefined,
  NativeFunction: ESNativeFunction,
  Object: ESObject,
};

/// Represents an "undefined" value
pub const ESUndefined = struct {
  pub fn toString(_: *const ESUndefined) []const u8 {
    return "undefined";
  }
};

pub const UNDEFINED = ESType {
  .Undefined = ESUndefined {},
};

pub const ESReference = struct {
  value: ESType,
  vartype: ESVarType,
  readonly: bool,
  assigned: bool,

  fn get(self: ESReference) ESType {
    return self.value.value;
  }
};

// Call Stack
pub const Instruction = union(enum) {
  /// Declares a variable
  Declare: struct {
    identifier: []const u8,
    type: ESVarType,
  },
  /// Sets a primitive value
  Set: struct {
    identifier: []const u8,
    value: []const u8,
  },
  // Sets an object value
  SetReference: struct {
    identifier: []const u8,
    value: ESType,
  },
  /// Reads a value into the register
  Read: []const u8,
  /// Writes the value from the register to the value
  Write: []const u8,
  /// Add a value to a register
  Add: []const u8,
  /// Loads an object property into the register
  ReadProperty: []const u8,
  /// Invokes the currently loaded property as a method
  Invoke: struct {
     args: ?[][]const u8,
  },
  /// Pushes the current scopes' register to the parent scope.
  Return: void,
};