import SwiftUI
import AppKit

@main
struct ProjectTrackerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = ProgressStore.shared

    var body: some Scene {
        // 選單列：只做預覽，點專案會打開主視窗編輯
        MenuBarExtra {
            MenuPreviewView()
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

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var launchedAsLoginItem = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        // 開機自動啟動時只待在選單列；使用者自己打開 App 時才顯示主視窗
        let event = NSAppleEventManager.shared().currentAppleEvent
        launchedAsLoginItem = event?.eventID == kAEOpenApplication &&
            event?.paramDescriptor(forKeyword: keyAEPropData)?.enumCodeValue == keyAELaunchedAsLogInItem
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !launchedAsLoginItem && ProcessInfo.processInfo.environment["PTRACK_NO_WINDOW"] == nil {
            MainWindowController.shared.show()
        }
    }

    /// App 已在執行時又從 Finder／Spotlight 打開：顯示主視窗。
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        MainWindowController.shared.show()
        return true
    }
}

/// 主視窗選到哪個專案（選單列面板與主視窗共用）。
final class MainWindowModel: ObservableObject {
    @Published var selectedID: String?
    @Published var search = ""
}

/// 用 AppKit 管理主視窗：可調整大小、記住位置（可拖到任何螢幕），開著時顯示在 Dock。
final class MainWindowController: NSObject, NSWindowDelegate {
    static let shared = MainWindowController()
    let model = MainWindowModel()
    private var window: NSWindow?

    func show(selecting id: String? = nil) {
        if let id { model.selectedID = id }
        if model.selectedID == nil { model.selectedID = ProgressStore.shared.projects.first?.id }
        let window = self.window ?? makeWindow()
        self.window = window
        NSApp.setActivationPolicy(.regular)
        // 先啟用 App 再把視窗拉到最前；在台前調度下也會被帶到中央
        NSApp.activate(ignoringOtherApps: true)
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        let root = MainWindowView()
            .environmentObject(ProgressStore.shared)
            .environmentObject(model)
            .environment(\.locale, Locale(identifier: "zh-Hant-TW"))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered, defer: false
        )
        window.title = "Project Tracker"
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = [.minSize]  // 只套用最小尺寸，視窗大小由使用者決定
        window.contentView = hosting
        window.contentMinSize = NSSize(width: 720, height: 480)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.center()
        // 記住上次的位置與大小（包括放在哪個螢幕）
        window.setFrameAutosaveName("ProjectTrackerMainWindow")
        return window
    }

    func windowWillClose(_ notification: Notification) {
        // 關掉主視窗後回到只在選單列待命，Dock 圖示消失
        DispatchQueue.main.async { NSApp.setActivationPolicy(.accessory) }
    }
}
