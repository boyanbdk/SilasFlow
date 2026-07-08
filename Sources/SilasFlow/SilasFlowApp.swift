import SwiftUI

/// SilasFlow — fully on-device push-to-talk dictation.
/// Hold the hotkey, speak, release: clean text lands at your cursor.
@main
struct SilasFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var controller = DictationController.shared

    var body: some Scene {
        MenuBarExtra {
            MenuContent()
                .environmentObject(controller)
        } label: {
            Image(systemName: controller.state.menuBarSymbol)
        }
        .menuBarExtraStyle(.window)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Headless pipeline test (--selftest file.wav): skip normal startup.
        if SelfTest.runIfRequested() { return }
        // Menu-bar only: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        DictationController.shared.start()
    }
}
