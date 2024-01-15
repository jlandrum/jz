const std = @import("std");
const Allocator = std.mem.Allocator;
const ArrayList = std.ArrayList;

const types = @import("types.zig");
const ESObject = types.ESObject;
const ESObjectImpl = types.ESObjectImpl;

pub const ESObjectManager = struct {
  allocator: Allocator,
  objects: ArrayList(*ESObjectImpl),

  pub fn init(allocator: Allocator) ESObjectManager {
    const objman = ESObjectManager{
      .allocator = allocator,
      .objects = ArrayList(*ESObjectImpl).init(allocator),
    };

    return objman;
  }

  pub fn createObject(self: *ESObjectManager) !ESObject {
    const obj = try ESObjectImpl.init(self.allocator);
    _ = try self.objects.append(obj);

    return ESObject {
      .value = obj,
    };
  }

  pub fn deinit(self: *ESObjectManager) void {
    while (self.objects.items.len > 0) {
      var item = self.objects.pop();
      item.deinit();
      self.allocator.destroy(item);
    }
    self.objects.deinit();
  }
};