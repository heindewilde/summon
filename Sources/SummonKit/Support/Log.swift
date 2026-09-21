import OSLog

public enum Log {
    public static let app = Logger(subsystem: "com.heindewilde.summon", category: "app")
    public static let store = Logger(subsystem: "com.heindewilde.summon", category: "store")
    public static let vault = Logger(subsystem: "com.heindewilde.summon", category: "vault")
    public static let search = Logger(subsystem: "com.heindewilde.summon", category: "search")
    public static let capture = Logger(subsystem: "com.heindewilde.summon", category: "capture")
    public static let insert = Logger(subsystem: "com.heindewilde.summon", category: "insert")
    public static let ai = Logger(subsystem: "com.heindewilde.summon", category: "intelligence")
}

public extension Duration {
    /// Milliseconds, rounded, for a log line. `Duration`'s own description is
    /// "0.812000123 seconds", which is precise and unreadable.
    var milliseconds: Int {
        let (seconds, attoseconds) = components
        return Int(seconds * 1000 + attoseconds / 1_000_000_000_000_000)
    }
}
