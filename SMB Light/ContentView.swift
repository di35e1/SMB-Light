import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    // Упростим список для более удобного парсинга в радиокнопки
    let themes = [
        ("trafficlight", "traffic"),
        ("apple", "apple"),
        ("myhart", "myhart"),
        ("flora", "flora"),
        ("fauna", "fauna")
    ]
    
    var body: some View {
        VStack(spacing: 15) {
            
            // MARK: - Настройки внешнего вида (Радиокнопки в ряд)
            HStack(alignment: .center, spacing: 15) {
                //Text("Theme")
                //.font(.headline)
                
                Spacer()
                
                // Проходим по всем темам и рисуем каждую как кнопку
                ForEach(themes, id: \.1) { theme in
                    let themeID = theme.1
                    let icons = IconTheme.get(theme: themeID)
                    
                    Button(action: {
                        settings.theme = themeID
                    }) {
                        HStack(spacing: 5) {
                            // Иконка радиокнопки
                            Image(systemName: settings.theme == themeID ? "dot.circle.fill" : "circle")
                                .foregroundColor(settings.theme == themeID ? .blue : .secondary)
                                .font(.system(size: 14))
                            
                            // Эмодзи из темы
                            Text("\(icons.online)\(icons.offline)")
                                .font(.system(size: 12))
                            
                            // Название темы (ID)
                            Text(themeID)
                                .foregroundColor(settings.theme == themeID ? .primary : .secondary)
                                .font(.system(size: 12, design: .default))
                        }
                        .padding(.horizontal, 4)
                        .contentShape(Rectangle()) // Чтобы кликалась вся область
                    }
                    .buttonStyle(PlainButtonStyle()) // Убираем стандартную обводку кнопки
                }
                
                Spacer()
            }
            .padding(.vertical, 1)
            
            Divider()
                .padding(.vertical, 1)
            
            // MARK: - Секции дисков
            DriveSectionView(title: "Priority Drives", isPriority: true, drives: $settings.priorityDrives)
            
            Divider()
                .padding(.vertical, 5)
            
            DriveSectionView(title: "Storage Drives", isPriority: false, drives: $settings.storageDrives)
        }
        .padding(20)
        
        .frame(minWidth: 650, maxWidth: 650, minHeight: 650, maxHeight: .infinity)
        
        .onDisappear {
            SettingsManager.shared.validateAndClean()
        }
    }
}

// MARK: - Переиспользуемая секция для дисков
struct DriveSectionView: View {
    var title: String
    var isPriority: Bool
    @Binding var drives: [Drive]

    @State private var selection: Set<Drive.ID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text("Name")
                    .fontWeight(.semibold)
                    .frame(width: 150, alignment: .leading)
                Text("Path")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .foregroundColor(.secondary)
            
            List(selection: $selection) {
                ForEach(drives) { drive in

                    // Создаем безопасную привязку для каждой строки
                    let safeBinding = Binding<Drive>(
                        get: {
                            // Если диск всё ещё в массиве — возвращаем его
                            if let index = drives.firstIndex(where: { $0.id == drive.id }) {
                                return drives[index]
                            }
                            // Если его удалила валидация — возвращаем "фантомную" копию во избежание краша
                            return drive
                        },
                        set: { newValue in
                            // Записываем новые данные, только если диск реально существует
                            if let index = drives.firstIndex(where: { $0.id == drive.id }) {
                                drives[index] = newValue
                            }
                        }
                    )
                    
                    // Передаем нашу безопасную привязку в DriveRowView
                    DriveRowView(drive: safeBinding)
                        .tag(drive.id)
                        .contextMenu {
                            Button(action: {
                                moveDriveToOtherList(drive)
                            }) {
                                Text(isPriority ? "Move to Storage Drives" : "Move to Priority Drives")
                                Image(systemName: "arrow.up.arrow.down")
                            }
                        }
                }
                .onMove { indices, newOffset in
                    drives.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
            .frame(minHeight: 160)
            
            HStack {
                Button(action: addDrive) {
                    Image(systemName: "plus")
                        .frame(width: 14, height: 14)
                }
                .frame(width: 28, height: 28)
                
                Button(action: removeSelectedDrives) {
                    Image(systemName: "minus")
                        .frame(width: 14, height: 14)
                }
                .frame(width: 28, height: 28)
                .disabled(selection.isEmpty)
                
                Spacer()
                
                Text("You can change the order by dragging rows")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func addDrive() {
        let newDrive = Drive(name: "Новый диск", path: "msk.off/example")
        drives.append(newDrive)
    }
    
    func removeSelectedDrives() {
        drives.removeAll { selection.contains($0.id) }
        selection.removeAll()
    }
    
    // МЕТОД ДЛЯ МГНОВЕННОГО ПЕРЕМЕЩЕНИЯ ДИСКА В ДРУГОЙ СПИСОК
    func moveDriveToOtherList(_ drive: Drive) {
        let settings = SettingsManager.shared
        
        if isPriority {
            settings.priorityDrives.removeAll { $0.id == drive.id }
            settings.storageDrives.append(drive)
        } else {
            settings.storageDrives.removeAll { $0.id == drive.id }
            settings.priorityDrives.append(drive)
        }
        
        // Сбрасываем выделение, чтобы строка не "застряла" в памяти
        selection.remove(drive.id)
    }
}

// MARK: - Отдельная строка для диска (для правильной работы фокуса)
struct DriveRowView: View {
    @Binding var drive: Drive

    // Индивидуальные состояния фокуса для конкретной строки
    @FocusState private var isNameFocused: Bool
    @FocusState private var isPathFocused: Bool
    
    var body: some View {
        HStack {
            TextField("Name", text: $drive.name)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 150)
                .focused($isNameFocused) // 1. Привязываем фокус
                .onSubmit {
                    SettingsManager.shared.validateAndClean()
                }
                .onChange(of: isNameFocused) { isFocused in
                    // 2. Если фокус пропал (стал false), сохраняем чистовик
                    if !isFocused {
                        SettingsManager.shared.validateAndClean()
                    }
                }
            
            TextField("Path", text: $drive.path)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .focused($isPathFocused) // 1. Привязываем фокус
                .onSubmit {
                    SettingsManager.shared.validateAndClean()
                }
                .onChange(of: isPathFocused) { isFocused in
                    // 2. Если фокус пропал (стал false), сохраняем чистовик
                    if !isFocused {
                        SettingsManager.shared.validateAndClean()
                    }
                }
        }
    }
}
