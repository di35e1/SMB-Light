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
            
            // 2. Очистка пути: убираем лишние пробелы и обратные слэши,
            // но оставляем кириллицу и слэши как есть.
            sanitized.path = sanitized.path
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\\", with: "/") // Заменяем возможные обратные слэши на прямые
                
            // 3. Если имя пустое — берем хвост пути
            if sanitized.name.trimmingCharacters(in: .whitespaces).isEmpty {
                let pathComponents = sanitized.path.split(separator: "/")
                sanitized.name = String(pathComponents.last ?? "Unknown")
            }
                
            return sanitized
        }
    
    // MARK: - Глобальная защита от дубликатов
    // Теперь функция проверяет текущий список с оглядкой на "соседний" список
    private func enforceUniqueness(for drives: [Drive], against otherDrives: [Drive]) -> [Drive] {
        var result: [Drive] = []
        
        // 1. Предзаполняем фильтры данными из соседнего списка,
        // чтобы знать, какие пути и имена уже заняты в другом блоке
        var seenNames = Set(otherDrives.map { $0.name.lowercased().trimmingCharacters(in: .whitespaces) })
        var seenPaths = Set(otherDrives.map { $0.path.lowercased().trimmingCharacters(in: .whitespaces) })
        
        for drive in drives {
            var currentDrive = drive
            
            var nameKey = currentDrive.name.lowercased().trimmingCharacters(in: .whitespaces)
            let pathKey = currentDrive.path.lowercased().trimmingCharacters(in: .whitespaces)
            
            // Разрешаем дублировать только базовый шаблон
            let isDefaultPath = (pathKey == "msk.rian/" || pathKey == "")
            
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
            var processed = priorityDrives.map { sanitizeDrive($0) }
            // Проверяем priorityDrives, учитывая то, что уже лежит в storageDrives
            processed = enforceUniqueness(for: processed, against: storageDrives)
            
            if priorityDrives != processed {
                priorityDrives = processed
            }
            if !isLoading { save() }
        }
    }
    
    var storageDrives: [Drive] = [] {
        willSet { objectWillChange.send() }
        didSet {
            var processed = storageDrives.map { sanitizeDrive($0) }
            // Проверяем storageDrives, учитывая то, что уже лежит в priorityDrives
            processed = enforceUniqueness(for: processed, against: priorityDrives)
            
            if storageDrives != processed {
                storageDrives = processed
            }
            if !isLoading { save() }
        }
    }
    
    private init() {
        load()
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
