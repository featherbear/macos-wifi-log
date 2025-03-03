const std = @import("std");
const ChildProcess = std.process.Child;

const LogStream = struct { eventMessage: []const u8, subsystem: []const u8, processID: c_int, timestamp: []const u8 };

const AppEvent = struct { timeString: []const u8, SSID: []const u8 };

const stdout = std.io.getStdOut().writer();
const stderr = std.io.getStdErr().writer();

pub fn emitEvent(event: AppEvent) !void {
    try stdout.print("{s},{s}\n", .{ event.timeString, event.SSID });
}

pub fn main() !void {
    var allocatorBacking = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = allocatorBacking.allocator();

    const filter = "subsystem == 'com.apple.IPConfiguration' AND formatString == '%s: SSID is now %@ (was %@)'";

    var proc = ChildProcess.init(&[_][]const u8{
        "/usr/bin/log", "stream", "--style", "ndjson",
        // You may need to add --info or --debug to the log stream command
        // "--info",
        "--predicate",  filter,
    }, allocator);
    proc.stdout_behavior = ChildProcess.StdIo.Pipe;
    proc.stderr_behavior = ChildProcess.StdIo.Ignore;
    try proc.spawn();

    // The max I've seen is around 5400 bytes
    var buffer: [8192]u8 = undefined;

    const reader = proc.stdout.?.reader();

    // Skip the first line: "Filtering the log data using ..."
    _ = try reader.readUntilDelimiter(&buffer, '\n');

    try stderr.print("Observing events...\n", .{});

    while (true) {
        const bytesRead = (try reader.readUntilDelimiter(&buffer, '\n')).len;
        const parsed = try std.json.parseFromSlice(LogStream, allocator, buffer[0..bytesRead], .{ .ignore_unknown_fields = true });
        defer parsed.deinit();

        const needle = "SSID is now ";
        const startIdx = std.mem.indexOf(u8, parsed.value.eventMessage, needle).? + needle.len;

        const needle2 = " (was ";
        const needle2Idx = std.mem.indexOfPos(u8, parsed.value.eventMessage, startIdx, needle2).?;

        const evtObject = AppEvent{
            //
            .timeString = parsed.value.timestamp,
            .SSID = parsed.value.eventMessage[startIdx..needle2Idx],
        };
        try emitEvent(evtObject);
    }
}
