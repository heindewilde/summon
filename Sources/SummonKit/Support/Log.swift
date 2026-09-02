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
