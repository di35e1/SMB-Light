import SwiftUI

@main
struct SmblightApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Оставляем пустышку, так как окнами мы теперь управляем сами
        Settings {
            EmptyView()
        }
    }
}
