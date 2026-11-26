import Foundation

#if PACEMARK_BENCH
/// Lets shared views report body runs to the Mac's `--bench-ui` counter. `BenchCounters` lives in
/// the Mac app, so it installs `sink` while counting is enabled. Only `PACEMARK_BENCH` builds
/// carry this; shipping builds get the no-op twin below.
@MainActor
public enum SharedBenchCounters {
    public static var sink: (@MainActor (String) -> Void)?

    public static func hit(_ name: String) {
        sink?(name)
    }
}
#else
public enum SharedBenchCounters {
    @inline(__always) public static func hit(_ name: String) {}
}
#endif
