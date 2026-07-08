import ServiceManagement
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
        // Diagnostic: --login-test verifies SMAppService register/unregister works
        // from the app's current location, then exits.
        if CommandLine.arguments.contains("--login-test") {
            print("login status before: \(SMAppService.mainApp.status.rawValue)")
            let ok = LoginItem.setEnabled(true)
            print("register ok=\(ok) status=\(SMAppService.mainApp.status.rawValue) (1=enabled)")
            LoginItem.setEnabled(false)
            print("after unregister status=\(SMAppService.mainApp.status.rawValue)")
            exit(ok && SMAppService.mainApp.status != .notFound ? 0 : 1)
        }
        // Headless pipeline test (--selftest file.wav): skip normal startup.
        if SelfTest.runIfRequested() { return }
        // Mic cycle test (--mictest N): verifies repeated record/stop cycles.
        if SelfTest.runMicTestIfRequested() { return }
        // Menu-bar only: no Dock icon, no main window.
        NSApp.setActivationPolicy(.accessory)
        DictationController.shared.start()
    }
}
