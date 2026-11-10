import SwiftUI

@main
struct ProjectTrackerApp: App {
    @StateObject private var store = ProgressStore()

    var body: some Scene {
        MenuBarExtra {
            ContentView()
                .environmentObject(store)
                .environment(\.locale, Locale(identifier: "zh-Hant-TW"))
        } label: {
            MenuBarLabel(count: store.attentionCount)
        }
        .menuBarExtraStyle(.window)
    }
}

struct MenuBarLabel: View {
    let count: Int

    var body: some View {
        if count > 0 {
            Image(systemName: "checklist")
            Text("\(count)")
        } else {
            Image(systemName: "checklist")
        }
    }
}
