//! The perfcount API with nothing behind it, for a build without
//! `-Dperfcount=true`: the same names as the perfcount module with
//! `enabled` off, so the probe code in relic_native.zig compiles to
//! nothing.

pub const enabled = false;

pub const Event = enum { instructions, cycles };
pub const Scope = enum { user, user_kernel };
pub const Coverage = enum { thread, process };
pub const Backend = enum { none };
pub const OpenError = error{Unsupported};
pub const ReadError = error{ReadFailed};

pub const Config = struct {};

pub const Sample = struct {
    pub inline fn get(_: Sample, _: Event) ?u64 {
        return null;
    }
    pub inline fn since(_: Sample, _: Sample, _: Sample) Sample {
        return .{};
    }
};

pub const Counters = struct {
    pub inline fn open(_: anytype) OpenError!Counters {
        return error.Unsupported;
    }
    pub inline fn read(_: *Counters) ReadError!Sample {
        return .{};
    }
    pub inline fn backend(_: *const Counters) Backend {
        return .none;
    }
    pub inline fn close(_: *Counters) void {}
};
