import Foundation
import os

// Logger Example
// Logger.network.info("SOCKS прокси успешно включен")
// Logger.system.error("Не удалось найти активный интерфейс")

extension Logger {
    /// Динамически получаем Bundle ID нашего приложения
    private static var subsystem: String {
        Bundle.main.bundleIdentifier ?? "com.default.smblight"
    }

    // Создаем статические логгеры для разных частей приложения
    static let network = Logger(subsystem: subsystem, category: "Network")
    static let ui = Logger(subsystem: subsystem, category: "UI")
    static let system = Logger(subsystem: subsystem, category: "System")
}
