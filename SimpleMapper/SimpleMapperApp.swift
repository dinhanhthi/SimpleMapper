import SwiftUI

@main
struct SimpleMapperApp: App {
    var body: some Scene {
        MenuBarExtra("SimpleMapper", systemImage: "keyboard") {
            Text("SimpleMapper")
        }
        .menuBarExtraStyle(.window)
    }
}
