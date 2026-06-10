import Foundation
import SystemConfiguration

class ProxyManager {
    
    /// Включает или выключает SOCKS прокси через вызов системной утилиты networksetup
    static func setSocksProxy(enabled: Bool) -> Bool {
        // 1. Узнаем системное имя интерфейса (например, en0)
        guard let interfaceName = getPrimaryInterfaceName() else {
            print("Не удалось определить активный интерфейс")
            return false
        }
        
        // 2. Узнаем человеческое имя интерфейса для networksetup (например, "Wi-Fi" или "Ethernet")
        guard let hardwareName = getHardwareName(for: interfaceName) else {
            print("Не удалось определить имя сети для \(interfaceName)")
            return false
        }
        
        let state = enabled ? "on" : "off"
        
        // 3. Запускаем утилиту напрямую (без sudo)
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-setsocksfirewallproxystate", hardwareName, state]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            
            // Если статус завершения 0 - команда успешно выполнена
            if task.terminationStatus == 0 {
                return true
            } else {
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                if let output = String(data: data, encoding: .utf8) {
                    print("Ошибка networksetup: \(output)")
                }
                return false
            }
        } catch {
            print("Ошибка запуска Process: \(error)")
            return false
        }
    }
    
    // Вспомогательная функция: получает BSD имя (например, en0)
    private static func getPrimaryInterfaceName() -> String? {
        guard let store = SCDynamicStoreCreate(nil, "SmblightStatus" as CFString, nil, nil) else { return nil }
        let ipv4Key = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetIPv4)
        guard let ipv4Dict = SCDynamicStoreCopyValue(store, ipv4Key) as? [String: Any],
              let primaryInterface = ipv4Dict[kSCDynamicStorePropNetPrimaryInterface as String] as? String else {
            return nil
        }
        return primaryInterface
    }
    
    // Вспомогательная функция: превращает "en0" в красивое имя (например, "Wi-Fi")
    private static func getHardwareName(for bsdName: String) -> String? {
        let task = Process()
        task.launchPath = "/usr/sbin/networksetup"
        task.arguments = ["-listnetworkserviceorder"]
        
        let pipe = Pipe()
        task.standardOutput = pipe
        
        do {
            try task.run()
            task.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            guard let output = String(data: data, encoding: .utf8) else { return nil }
            
            let lines = output.components(separatedBy: .newlines)
            for i in 0..<lines.count {
                if lines[i].contains("Device: \(bsdName)") {
                    // Предыдущая строка содержит нужное имя (например: "(1) Wi-Fi")
                    if i > 0 {
                        let nameLine = lines[i-1]
                        if let name = nameLine.components(separatedBy: ") ").last {
                            return name
                        }
                    }
                }
            }
        } catch {
            return nil
        }
        return nil
    }
    
    /// Проверяет, включен ли сейчас SOCKS прокси на системном уровне (работает без паролей)
    static func isSocksProxyEnabled() -> Bool {
        // Создаем подключение к динамическому хранилищу состояния системы
        guard let store = SCDynamicStoreCreate(nil, "SmblightStatus" as CFString, nil, nil) else {
            return false
        }
        
        // Получаем специальный ключ для глобального состояния прокси в macOS
        let globalProxyKey = SCDynamicStoreKeyCreateNetworkGlobalEntity(nil, kSCDynamicStoreDomainState, kSCEntNetProxies)
        
        // Читаем словарь настроек
        if let proxyDict = SCDynamicStoreCopyValue(store, globalProxyKey) as? [String: Any] {
            // Извлекаем значение флага kSCPropNetProxiesSOCKSEnable (обычно это Int: 1 или 0)
            if let socksEnabled = proxyDict[kSCPropNetProxiesSOCKSEnable as String] as? Int {
                return socksEnabled == 1
            }
        }
        return false
    }
    
}
