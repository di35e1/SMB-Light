import Foundation
import Combine

struct Drive: Codable, Hashable, Identifiable {
    var id: UUID
    var name: String
    var path: String
    
    init(id: UUID = UUID(), name: String, path: String) {
        self.id = id
        self.name = name
        self.path = path
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = (try? container.decode(UUID.self, forKey: .id)) ?? UUID()
        self.name = try container.decode(String.self, forKey: .name)
        self.path = try container.decode(String.self, forKey: .path)
    }
}

class SettingsManager: ObservableObject {
    static let shared = SettingsManager()

    private var isLoading = true

    func sanitizeDrive(_ drive: Drive) -> Drive {
        var sanitized = drive
            
        // 1. Убираем "smb://"
        if sanitized.path.lowercased().hasPrefix("smb://") {
            sanitized.path = String(sanitized.path.dropFirst(6))
        }
        
        // 2. Очистка пути: убираем лишние пробелы и обратные слэши
        sanitized.path = sanitized.path
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\", with: "/")
            
        // 3. Если имя пустое — берем хвост пути
        if sanitized.name.trimmingCharacters(in: .whitespaces).isEmpty {
            let pathComponents = sanitized.path.split(separator: "/")
            sanitized.name = String(pathComponents.last ?? "Unknown")
        }
            
        return sanitized
    }
    
    // Вспомогательная функция: нормализует путь для корректного сравнения
    private func normalizePathKey(_ path: String) -> String {
        var key = path.lowercased().trimmingCharacters(in: .whitespaces)
        // Если на конце есть один или несколько слэшей — отрезаем их
        while key.hasSuffix("/") {
            key.removeLast()
        }
        return key
    }
    
    // MARK: - Глобальная защита от дубликатов
    private func enforceUniqueness(for drives: [Drive], against otherDrives: [Drive]) -> [Drive] {
        var result: [Drive] = []
        
        var seenNames = Set(otherDrives.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        // ИСПОЛЬЗУЕМ НОВУЮ ФУНКЦИЮ ЗДЕСЬ:
        var seenPaths = Set(otherDrives.map { normalizePathKey($0.path) })
        
        for drive in drives {
            var currentDrive = drive
            
            var nameKey = currentDrive.name.lowercased().trimmingCharacters(in: .whitespaces)
            // ИСПОЛЬЗУЕМ НОВУЮ ФУНКЦИЮ ЗДЕСЬ:
            let pathKey = normalizePathKey(currentDrive.path)
            
            // ВАЖНО: Базовый шаблон теперь сравниваем без слэша на конце
            let isDefaultPath = (pathKey == "msk.rian" || pathKey == "")
            
            // Проверка путей (сквозная)
            if seenPaths.contains(pathKey) && !isDefaultPath {
                continue // Путь уже есть либо в этом, либо в соседнем списке -> удаляем дубликат
            }
            
            if !isDefaultPath {
                seenPaths.insert(pathKey)
            }
            
            // Проверка имен (сквозная)
            if seenNames.contains(nameKey) {
                var counter = 1
                let originalName = currentDrive.name
                
                while seenNames.contains(nameKey) {
                    currentDrive.name = "\(originalName) (\(counter))"
                    nameKey = currentDrive.name.lowercased().trimmingCharacters(in: .whitespaces)
                    counter += 1
                }
            }
            seenNames.insert(nameKey)
            
            result.append(currentDrive)
        }
        
        return result
    }
    
    var theme: String = "trafficlight" {
        willSet { objectWillChange.send() }
        didSet { if !isLoading { save() } }
    }
    
    var priorityDrives: [Drive] = [] {
        willSet { objectWillChange.send() }
        didSet {
            // Оставляем только тихое сохранение сырого ввода
            if !isLoading { save() }
        }
    }
    
    var storageDrives: [Drive] = [] {
        willSet { objectWillChange.send() }
        didSet {
            // Оставляем только тихое сохранение сырого ввода
            if !isLoading { save() }
        }
    }
    
    private init() {
        load()
    }
    
    // MARK: - Валидация
    /// Вызывайте эту функцию из UI, когда пользователь завершил редактирование
    func validateAndClean() {
        // Устанавливаем флаг, чтобы избежать бесконечного цикла, так как мы будем изменять массивы
        isLoading = true
        defer {
            isLoading = false
            save() // Окончательно сохраняем очищенные данные
        }
        
        var processedPriority = priorityDrives.map { sanitizeDrive($0) }
        var processedStorage = storageDrives.map { sanitizeDrive($0) }
        
        // Сквозная проверка на уникальность
        processedPriority = enforceUniqueness(for: processedPriority, against: processedStorage)
        processedStorage = enforceUniqueness(for: processedStorage, against: processedPriority)
        
        // Применяем изменения только если они реально есть, чтобы не дергать UI лишний раз
        if priorityDrives != processedPriority {
            priorityDrives = processedPriority
        }
        if storageDrives != processedStorage {
            storageDrives = processedStorage
        }
    }
    
    // MARK: - Сохранение и загрузка
    func save() {
        guard !isLoading else { return }
        
        let encoder = JSONEncoder()
        UserDefaults.standard.set(theme, forKey: "Theme")
        
        if let encodedPriority = try? encoder.encode(priorityDrives) {
            UserDefaults.standard.set(encodedPriority, forKey: "PriorityDrives")
        }
        
        if let encodedStorage = try? encoder.encode(storageDrives) {
            UserDefaults.standard.set(encodedStorage, forKey: "StorageDrives")
        }
        
        UserDefaults.standard.synchronize()
    }
    
    func load() {
        isLoading = true
        defer { isLoading = false }

        let decoder = JSONDecoder()
        
        if let savedTheme = UserDefaults.standard.string(forKey: "Theme") {
            self.theme = savedTheme
        }
        
        if let data = UserDefaults.standard.data(forKey: "PriorityDrives"),
           let savedPriority = try? decoder.decode([Drive].self, from: data) {
            self.priorityDrives = savedPriority
        } else {
            self.priorityDrives = [
                Drive(name: "Photo_share", path: "msk.rian/PublicFolders/Photo_share")
            ]
        }
        
        if let data = UserDefaults.standard.data(forKey: "StorageDrives"),
           let savedStorage = try? decoder.decode([Drive].self, from: data) {
            self.storageDrives = savedStorage
        } else {
            self.storageDrives = [
                Drive(name: "Диск W", path: "msk.rian/PublicFolders/W")
            ]
        }
        
        // При загрузке приложения тоже прогоняем валидацию на случай, если
        // пользователь закрыл приложение до того, как сработала проверка.
        DispatchQueue.main.async { [weak self] in
            self?.validateAndClean()
        }
    }
    
    /// Импортирует настройки из выбранного пользователем файла YAML
        func importFromYAML(at url: URL) -> Bool {
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                return false
            }

            var currentSection = ""
            var importedPriority: [Drive] = []
            var importedStorage: [Drive] = []
            var importedTheme: String?

            let lines = content.components(separatedBy: .newlines)

            for line in lines {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.isEmpty { continue }

                // 1. Ищем тему
                if trimmed.hasPrefix("\"Theme\":") {
                    let parts = trimmed.components(separatedBy: ":")
                    if parts.count >= 2 {
                        importedTheme = parts[1].trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "\"", with: "")
                    }
                }
                // 2. Ищем целевые секции
                else if trimmed.hasPrefix("\"NetworkDrivesPriority\":") {
                    currentSection = "Priority"
                } else if trimmed.hasPrefix("\"NetworkDrives\":") {
                    currentSection = "Storage"
                }
                // 3. БЛОКИРУЕМ ДРУГИЕ СЕКЦИИ: если строка заканчивается на ":" (например, "UserCommands": или "SocksServers":)
                else if trimmed.hasSuffix(":") {
                    // Переводим парсер в режим игнорирования
                    currentSection = "Ignore"
                }
                // 4. Парсим списки (только если мы находимся в нужной секции)
                else if trimmed.hasPrefix("-") {
                    // Если мы в блоке Ignore, просто переходим к следующей строке
                    guard currentSection == "Priority" || currentSection == "Storage" else { continue }
                    
                    let rawStr = String(trimmed.dropFirst(1)).trimmingCharacters(in: .whitespaces)
                    let parts = rawStr.components(separatedBy: ": \"")
                    
                    if parts.count == 2 {
                        let name = parts[0].replacingOccurrences(of: "\"", with: "")
                        var path = parts[1].replacingOccurrences(of: "\"", with: "")
                        
                        if path.hasPrefix("smb://") {
                            path = String(path.dropFirst(6))
                        }
                        
                        let drive = Drive(name: name, path: path)
                        
                        if currentSection == "Priority" {
                            importedPriority.append(drive)
                        } else if currentSection == "Storage" {
                            importedStorage.append(drive)
                        }
                    }
                }
            }

            // Если в файле вообще не нашлось нужных данных — выходим с ошибкой
            if importedTheme == nil && importedPriority.isEmpty && importedStorage.isEmpty {
                return false
            }

            // Обновляем данные на главном потоке
            DispatchQueue.main.async {
                self.isLoading = true
                
                if let theme = importedTheme {
                    self.theme = theme
                }
                if !importedPriority.isEmpty {
                    self.priorityDrives = importedPriority
                }
                if !importedStorage.isEmpty {
                    self.storageDrives = importedStorage
                }
                
                self.isLoading = false
                self.validateAndClean()
            }

            return true
        }
}

struct IconTheme {
    let online: String
    let offline: String
    
    static let themes: [String: IconTheme] = [
        "trafficlight": IconTheme(online: "🟢", offline: "🔴"),
        "apple": IconTheme(online: "🍏", offline: "🍎"),
        "myhart": IconTheme(online: "💚", offline: "💔"),
        "flora": IconTheme(online: "🌵", offline: "🍄"),
        "fauna": IconTheme(online: "🐸", offline: "🐽")
    ]
    
    static func get(theme: String) -> IconTheme {
        return themes[theme] ?? themes["trafficlight"]!
    }
}
