import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings = SettingsManager.shared
    
    let themes = [
        ("Светофор (🟢 / 🔴)", "trafficlight"),
        ("Яблоко (🍏 / 🍎)", "apple"),
        ("Сердца (💚 / 💔)", "myhart"),
        ("Флора (🌵 / 🍄)", "flora"),
        ("Фауна (🐸 / 🐽)", "fauna")
    ]
    
    var body: some View {
        VStack(spacing: 15) {
            
            // MARK: - Настройки внешнего вида (Верхняя строка)
            HStack {
                Text("Стиль иконок:")
                    .font(.headline)
                
                Spacer()
                
                Picker("", selection: $settings.theme) {
                    ForEach(themes, id: \.1) { theme in
                        Text(theme.0).tag(theme.1)
                    }
                }
                .labelsHidden()
                .frame(width: 200)
            }
            
            Divider()
                .padding(.vertical, 5)
            
            // MARK: - Секции дисков
            // Передаем флаг isPriority, чтобы секция знала, кем она является
            DriveSectionView(title: "Priority Drives (в строке меню)", isPriority: true, drives: $settings.priorityDrives)
            
            Divider()
                .padding(.vertical, 5)
            
            DriveSectionView(title: "Storage Drives", isPriority: false, drives: $settings.storageDrives)
        }
        .padding(20)
        .frame(width: 550, height: 650)
    }
}

// MARK: - Переиспользуемая секция для дисков
struct DriveSectionView: View {
    var title: String
    var isPriority: Bool // <-- Флаг для логики перемещения
    @Binding var drives: [Drive]
    
    @State private var selection: Set<Drive.ID> = []
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
            
            HStack {
                Text("Имя")
                    .fontWeight(.semibold)
                    .frame(width: 150, alignment: .leading)
                Text("Путь")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 14)
            .padding(.top, 5)
            .foregroundColor(.secondary)
            
            List(selection: $selection) {
                ForEach($drives) { $drive in
                    HStack {
                        TextField("Имя", text: $drive.name)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                            .frame(width: 150)
                        
                        TextField("Путь", text: $drive.path)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }
                    .tag(drive.id)
                    // ДОБАВЛЯЕМ КОНТЕКСТНОЕ МЕНЮ (ПРАВЫЙ КЛИК)
                    .contextMenu {
                        Button(action: {
                            moveDriveToOtherList(drive)
                        }) {
                            Text(isPriority ? "Переместить в Storage Drives" : "Переместить в Priority Drives")
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
                
                Text("Можно менять порядок перетаскиванием строк")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
    
    func addDrive() {
        let newDrive = Drive(name: "Новый диск", path: "msk.rian/")
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
