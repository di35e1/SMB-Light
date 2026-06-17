import Cocoa
import Network
import ServiceManagement
import SwiftUI
import Combine
import os
import UniformTypeIdentifiers

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    var statusItem: NSStatusItem!
    var menu: NSMenu!
    var proxyMenuItem: NSMenuItem?
    var timer: Timer?
    let monitor = NWPathMonitor()
    var isNetworkAvailable = false
    var settingsWindow: NSWindow?
    var cancellables = Set<AnyCancellable>()
    
    var isImportPanelOpen = false // Флаг для защиты от двойного открытия окна импорта
    let settings = SettingsManager.shared

    
    func setupBindings() {
        settings.objectWillChange
        // Ждем 0.5 секунды после окончания ввода текста в настройках
            .debounce(for: .milliseconds(500), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                // Пересобираем меню и сразу обновляем статусы (кружочки)
                self?.buildMenu()
                self?.updateStatus()
            }
            .store(in: &cancellables)
    }
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        // 1. ПРОВЕРКА НА ВТОРУЮ КОПИЮ
        // Получаем Bundle ID приложения (например, com.user.smblight)
        if let bundleID = Bundle.main.bundleIdentifier {
            // Ищем все запущенные процессы с таким же ID
            let runningApps = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            // Если найдено больше одного процесса (то есть мы и кто-то еще),
            // тихо убиваем текущую копию до того, как она создаст иконку в меню.
            if runningApps.count > 1 {
                NSApp.terminate(nil)
                return
            }
        }
        // Инициализация статус-бара
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "SMB..."
        
        setupNetworkMonitor()
        setupBindings()
        buildMenu()
        updateStatus()
        
        // Слушаем ПОДКЛЮЧЕНИЕ дисков
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didMountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            //print("Событие: диск смонтирован")
            Logger.network.info("Диск смонтирован")
            self?.updateStatus()
        }
        
        // Слушаем ОТКЛЮЧЕНИЕ дисков
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didUnmountNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            Logger.network.info("Диск размонтирован")
            self?.updateStatus()
        }
    }
    
    func setupNetworkMonitor() {
        monitor.pathUpdateHandler = { path in
            self.isNetworkAvailable = path.status == .satisfied
            DispatchQueue.main.async {
                self.updateStatus()
            }
        }
        let queue = DispatchQueue(label: "NetworkMonitor")
        monitor.start(queue: queue)
    }
    
    func buildMenu() {
        menu = NSMenu()
        
        // Priority Drives
        menu.addItem(NSMenuItem(title: "Open Priority drives", action: #selector(openPriorityDrives), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Force unmount", action: #selector(forceUnmount), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Priority drives:", action: nil, keyEquivalent: ""))
        
        for drive in settings.priorityDrives {
            let item = NSMenuItem(title: drive.name, action: #selector(driveClicked(_:)), keyEquivalent: "")
            item.representedObject = drive
            menu.addItem(item)
        }
        
        // Storage Drives
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Storage drives:", action: nil, keyEquivalent: ""))
        
        for drive in settings.storageDrives {
            let item = NSMenuItem(title: drive.name, action: #selector(driveClicked(_:)), keyEquivalent: "")
            item.representedObject = drive
            menu.addItem(item)
        }
        
        // Tools & Settings
        //        menu.addItem(NSMenuItem.separator())
        //        menu.addItem(NSMenuItem(title: "🤖 Editor", action: #selector(openEditor), keyEquivalent: ""))
        //        menu.addItem(NSMenuItem(title: "🖥️ Mediabank", action: #selector(openMediabank), keyEquivalent: ""))
        
        let dangerZone = NSMenuItem(title: "Preferences", action: nil, keyEquivalent: "")
        let dangerMenu = NSMenu()
        
        dangerMenu.addItem(NSMenuItem(title: "Terminal", action: #selector(openTerminal), keyEquivalent: ""))
        dangerMenu.addItem(NSMenuItem(title: "killall Finder", action: #selector(killFinder), keyEquivalent: ""))
        dangerMenu.addItem(NSMenuItem(title: "Import Settings...", action: #selector(importSettingsClicked(_:)), keyEquivalent: ""))
        dangerMenu.addItem(NSMenuItem.separator())
        
        // Автозагрузка (Modern API macOS 13+)
        // Автозагрузка (через современный SMAppService.mainApp)
        if #available(macOS 13.0, *) {
            let loginItem = NSMenuItem(title: "Open at login", action: #selector(toggleAutostart(_:)), keyEquivalent: "")
            loginItem.target = self
            loginItem.state = (SMAppService.mainApp.status == .enabled) ? .on : .off
            dangerMenu.addItem(loginItem)
        }
        
        dangerMenu.addItem(NSMenuItem(title: "Settings", action: #selector(showSettings), keyEquivalent: ""))
       
        dangerZone.submenu = dangerMenu
        menu.addItem(NSMenuItem.separator())
        menu.addItem(dangerZone)
        menu.addItem(NSMenuItem.separator())
        
        if isCurrentUserAdmin() {
            // Proxy toggle
            let proxyItem = NSMenuItem(title: "SOCKS Proxy", action: #selector(toggleProxy(_:)), keyEquivalent: "")
            proxyItem.state = (ProxyManager.isSocksProxyEnabled()) ? .on : .off
            self.proxyMenuItem = proxyItem
            menu.addItem(proxyItem)
            menu.addItem(NSMenuItem.separator())
        } else {
            // Если пользователь не админ, очищаем ссылку, чтобы кнопка точно нигде не всплыла
            self.proxyMenuItem = nil
        }
        
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: ""))
        
        statusItem.menu = menu
    }
    
    @objc func updateStatus() {
        guard isNetworkAvailable else {
            statusItem.button?.title = "Network offline"
            return
        }
        
        // Получаем словарь [путь: точка_монтирования]
        let mountedMap = getMountedSMBDrives()
        
        let currentTheme = IconTheme.get(theme: settings.theme)
        var highlights: [String] = []
        
        for item in menu.items {
            if let drive = item.representedObject as? Drive {
                
                // Приводим путь из настроек к нижнему регистру
                let pathLower = drive.path.lowercased()
                
                // Проверяем как закодированный путь (системный стандарт), так и оригинал на всякий случай
                let isMounted = mountedMap.keys.contains(pathLower)
                
                if isMounted {
                    item.title = "\(currentTheme.online) Open \(drive.name)"
                    item.state = .on
                } else {
                    item.title = "\(currentTheme.offline) Connect to \(drive.name)"
                    item.state = .off
                }
                
                if settings.priorityDrives.contains(where: { $0.id == drive.id }) {
                    highlights.append(isMounted ? currentTheme.online : currentTheme.offline)
                }
            }
        }
        
        statusItem.button?.title = "SMB " + highlights.joined(separator: " | ")
        
        let isProxyOn = ProxyManager.isSocksProxyEnabled()
        if isProxyOn {
            statusItem.button?.title  += " | 👽"
        }
        
        if let proxyItem = self.proxyMenuItem {
            proxyItem.state = isProxyOn ? .on : .off
            proxyItem.title = isProxyOn ? "👽 Disable SOCKS Proxy" : "Enable SOCKS Proxy"
        }
        
    }
    
    func getMountedSMBDrives() -> [String: String] {
        let task = Process()
        let pipe = Pipe()
        task.executableURL = URL(fileURLWithPath: "/sbin/mount")
        task.arguments = ["-t", "smbfs"]
        task.standardOutput = pipe
        try? task.run()
        
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        let output = String(data: data, encoding: .utf8) ?? ""
        
        var mapping: [String: String] = [:]
        let lines = output.components(separatedBy: .newlines)
        
        for line in lines {
            // Ищем строку вида: //user@path on /Volumes/Name (smbfs...)
            if let onRange = line.range(of: " on ") {
                let fullSource = String(line[..<onRange.lowerBound])
                let volumePath = String(line[onRange.upperBound...].split(separator: " ")[0])
                
                // Чистим сетевой путь от префикса //user@
                var path = fullSource
                if let atRange = path.range(of: "@") {
                    path = String(path[atRange.upperBound...])
                } else if path.hasPrefix("//") {
                    path = String(path.dropFirst(2))
                }
                
                let cleanPath = path.removingPercentEncoding?.lowercased() ?? path.lowercased()
                mapping[cleanPath] = volumePath
                // mapping[path.lowercased()] = volumePath
            }
        }
        return mapping
    }
    
    // MARK: - Actions
    
    @objc func toggleProxy(_ sender: NSMenuItem) {
        let isCurrentlyOn = sender.state == .on
        let newState = !isCurrentlyOn
        
        // Вызываем метод только с одним параметром — включить или выключить
        let success = ProxyManager.setSocksProxy(enabled: newState)
        
        if success {
            sender.state = newState ? .on : .off
            sender.title = newState ? "Disable SOCKS Proxy" : "Enable SOCKS Proxy"
            Logger.network.info("Статус SOCKS прокси изменен: \(newState)")
        } else {
            Logger.network.error("Не удалось изменить статус прокси (возможно, отменен ввод пароля)")
        }
    }
    
    
    @objc func driveClicked(_ sender: NSMenuItem) {
        guard let drive = sender.representedObject as? Drive else { return }
        
        // 1. Получаем карту текущих подключений (путь из настроек : реальный путь в /Volumes)
        let mountedMap = getMountedSMBDrives()
        
        // 2. Ищем, смонтирован ли диск (игнорируя регистр)
        if let volumePath = mountedMap[drive.path.lowercased()] {
            // ДИСК УЖЕ ПОДКЛЮЧЕН: Открываем его в Finder
            let url = URL(fileURLWithPath: volumePath)
            NSWorkspace.shared.open(url)
            Logger.network.info("Диск уже подключен, открываю через Finder: \(volumePath)")
        } else {
            // ДИСК НЕ ПОДКЛЮЧЕН: Выполняем стандартное монтирование
            Logger.network.info("Диск не подключен, запускаю SMB-подключение: \(drive.path)")
            
            let urlString = "smb://\(drive.path)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc func openPriorityDrives() {
        for drive in settings.priorityDrives {
            let urlString = "smb://\(drive.path)".addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            if let url = URL(string: urlString) {
                NSWorkspace.shared.open(url)
            }
        }
    }
    
    @objc func forceUnmount() {
        let alert = NSAlert()
        alert.messageText = "Отключить все сетевые диски?"
        alert.addButton(withTitle: "Да, отключить")
        alert.addButton(withTitle: "Нет, я еще подумаю")
        
        if alert.runModal() == .alertFirstButtonReturn {
            let mountedMap = getMountedSMBDrives()
            let allDrives = SettingsManager.shared.priorityDrives + SettingsManager.shared.storageDrives
            
            for drive in allDrives {
                // Ищем реальную точку монтирования по пути из настроек
                if let volumePath = mountedMap[drive.path.lowercased()] {
                    Logger.network.info("Принудительное размонтирование: \(volumePath)")
                    
                    let task = Process()
                    task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
                    task.arguments = ["unmount", "force", volumePath]
                    try? task.run()
                }
            }
        }
    }
    
    @available(macOS 13.0, *)
    @objc func toggleAutostart(_ sender: NSMenuItem) {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
                sender.state = .off
            } else {
                try SMAppService.mainApp.register()
                sender.state = .on
            }
        } catch let error as NSError {
            Logger.system.error("Ошибка автозапуска: \(error)")
            
            // Обработка блокировки тумблера в Системных настройках (Operation not permitted)
            if error.code == 1 {
                let alert = NSAlert()
                alert.messageText = "Требуется разрешение системы"
                alert.informativeText = "Автозапуск заблокирован в настройках macOS.\nПожалуйста, включите приложение в разделе «Объекты входа»."
                alert.addButton(withTitle: "Открыть Настройки")
                alert.addButton(withTitle: "Отмена")
                
                if alert.runModal() == .alertFirstButtonReturn {
                    // Прямой вызов системного окна без проверок на версию ОС
                    SMAppService.openSystemSettingsLoginItems()
                }
            }
            
            sender.state = .off
        }
    }
    
    @objc func openTerminal() {
        NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"), configuration: NSWorkspace.OpenConfiguration(), completionHandler: nil)
    }
    
    @objc func killFinder() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
        task.arguments = ["Finder"]
        try? task.run()
    }
    
    //    @objc func openEditor() {
    //        NSWorkspace.shared.open(URL(string: "https://")!)
    //    }
    //
    //    @objc func openMediabank() {
    //        NSWorkspace.shared.open(URL(string: "https://")!)
    //    }
    
    @objc func showSettings() {
        // 2. ВКЛЮЧАЕМ ОТОБРАЖЕНИЕ В ДОКЕ
        NSApp.setActivationPolicy(.regular)
        
        // Если окно уже было создано, просто выводим его на передний план
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            window.makeFirstResponder(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        
        // Если окна нет, создаем его и оборачиваем наш SwiftUI-интерфейс
        let hostingController = NSHostingController(rootView: SettingsView())
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 650, height: 650),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.center()
        window.level = .floating
        window.title = "SMB Light settings"
        window.contentViewController = hostingController
        window.isReleasedWhenClosed = false // чтобы окно не уничтожалось при закрытии на крестик
        
        // НАЗНАЧАЕМ ДЕЛЕГАТА (чтобы отловить момент закрытия окна)
        window.delegate = self
        
        self.settingsWindow = window
        
        // Выводим окно поверх всех
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    // 3. ОТЛАВЛИВАЕМ ЗАКРЫТИЕ ОКНА
    func windowWillClose(_ notification: Notification) {
        // Возвращаем приложение в фоновый режим (прячем иконку из Дока)
        NSApp.setActivationPolicy(.accessory)
        self.settingsWindow = nil
    }
    
    /// Проверяет, состоит ли текущий пользователь мака в группе admin
    private func isCurrentUserAdmin() -> Bool {
        // В macOS группа администраторов (admin) всегда имеет ID 80
        let adminGroupID: gid_t = 80
        
        // Получаем количество групп, в которых состоит пользователь
        let groupCount = getgroups(0, nil)
        if groupCount <= 0 { return false }
        
        // Читаем ID всех этих групп
        var groups = [gid_t](repeating: 0, count: Int(groupCount))
        getgroups(groupCount, &groups)
        
        // Возвращаем true, если 80 есть в списке дополнительных групп
        // или является основной группой (getgid)
        return groups.contains(adminGroupID) || getgid() == adminGroupID
    }
    
    @objc func importSettingsClicked(_ sender: NSMenuItem) {
        // 1. ЗАЩИТА: Если окно уже открыто — просто игнорируем нажатие
        guard !isImportPanelOpen else { return }
        isImportPanelOpen = true
        
        NSApp.activate(ignoringOtherApps: true)
        
        let openPanel = NSOpenPanel()
        openPanel.title = "Выберите файл settings.yaml"
        openPanel.showsResizeIndicator = true
        openPanel.showsHiddenFiles = true
        openPanel.allowsMultipleSelection = false
        openPanel.canChooseDirectories = false
        openPanel.canChooseFiles = true
        
        openPanel.allowedContentTypes = [
            UTType(filenameExtension: "yaml"),
            //UTType(filenameExtension: "yml")
        ].compactMap { $0 }
        
        // Открываем панель модально
        // ВАЖНО: Добавляем [weak self], чтобы безопасно обращаться к флагу внутри замыкания
        openPanel.begin { [weak self] response in
            
            // 2. СНИМАЕМ БЛОКИРОВКУ, как только окно закрылось (кнопкой ОК или Отмена)
            self?.isImportPanelOpen = false
            
            if response == .OK, let fileURL = openPanel.url {
                let isSuccess = SettingsManager.shared.importFromYAML(at: fileURL)
                
                DispatchQueue.main.async {
                    let alert = NSAlert()
                    if isSuccess {
                        alert.messageText = "Импорт завершен"
                        alert.informativeText = "Настройки успешно загружены из файла и применены."
                        alert.alertStyle = .informational
                    } else {
                        alert.messageText = "Ошибка импорта"
                        alert.informativeText = "Не удалось распознать структуру Smblight в выбранном файле."
                        alert.alertStyle = .warning
                    }
                    alert.addButton(withTitle: "OK")
                    alert.runModal()
                }
            }
        }
    }
}
