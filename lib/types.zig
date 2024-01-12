const std = @import("std");

// Dynamic Vars
pub const ESVarType = enum {
  CONST, VAR, LET
};

pub const ESNumber = struct {
  value: f64,

  pub fn add(self: *ESNumber, val: f64) void {
    self.value += val;
  }

  pub fn toString(self: *const ESNumber) []const u8 {
    var integer: bool = self.value == std.math.round(self.value);
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

pub const ESString = struct {
  value: []const u8,

  pub fn toString(self: *const ESString) []const u8 {
    return self.value;
  }
};

pub const ESType = union(enum) {
  Number: ESNumber,
  String: ESString,
  // Function: *const ESFunction,
  Undefined: ESUndefined,
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
  /// Sets a value
  Set: struct {
    identifier: []const u8,
    value: []const u8,
  },
  /// Reads a value into the register
  Read: []const u8,
  /// Writes the value from the register to the value
  Write: []const u8,
  /// Add a value to a register
  Add: []const u8,
};