const std = @import("std");

const types = @import("types.zig");
const ESNumber = types.ESNumber;
const ESVar = types.ESVar;
const ESType = types.ESType;

pub fn isNumber(str: []const u8) bool {
  if (str.len == 0) return false;
  const c = str[0];
  return (c >= '0' and c <= '9') or (c == '.') or (c == '-') or (std.mem.eql(u8, str, "NaN")) or (std.mem.eql(u8, str, "Infinity") or (std.mem.eql(u8, str, "-Infinity")));
}

pub fn parseNumber(str: []const u8) f64 {
    if (!isNumber(str)) { return std.math.nan(f64); }
    if (std.mem.eql(u8, str, "NaN")) { return std.math.nan(f64); }
    if (std.mem.eql(u8, str, "Infinity")) { return std.math.inf(f64); }
    if (std.mem.eql(u8, str, "-Infinity")) { return -std.math.inf(f64); }
    var number = std.fmt.parseFloat(f64, str) catch {
      return std.math.nan(f64);
    };
    return number;
}

pub const EmptyArray = &[_][]const u8{};

// pub fn add(a: ESType, b: ESType) ESType {
//
// }
