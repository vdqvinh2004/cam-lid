import Darwin

/// Session deadlines include system sleep; wall-clock changes cannot extend them.
public enum ContinuousTime {
    private static let secondsPerTick: Double = {
        var info = mach_timebase_info_data_t()
        mach_timebase_info(&info)
        return Double(info.numer) / Double(info.denom) / 1_000_000_000
    }()
    public static var now: Double { Double(mach_continuous_time()) * secondsPerTick }
}
