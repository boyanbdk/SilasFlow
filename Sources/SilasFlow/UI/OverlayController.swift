import AppKit
import SwiftUI

/// Owns the floating recording-indicator panel (the "pill").
/// The panel never activates, never takes keyboard focus, and is click-through,
/// so the app being dictated into keeps focus the whole time.
/// Purely cosmetic: any failure here must never block the dictation pipeline.
@MainActor
final class OverlayController: ObservableObject {
    enum Phase {
        case listening
        case processing
        case error
    }

    static let barCount = 12

    @Published var phase: Phase = .listening
    /// Scrolling history of recent mic loudness values (newest last).
    @Published var levels: [Float] = Array(repeating: 0, count: OverlayController.barCount)

    private var panel: NSPanel?
    private var hideWorkItem: DispatchWorkItem?

    // MARK: - Pipeline hooks

    func showListening() {
        hideWorkItem?.cancel()
        levels = Array(repeating: 0, count: Self.barCount)
        phase = .listening
        presentPanel()
    }

    func showProcessing() {
        phase = .processing
    }

    /// Brief red tint, then hide.
    func showErrorAndHide() {
        phase = .error
        hide(after: 1.2)
    }

    func hide(after delay: TimeInterval = 0) {
        hideWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.panel?.orderOut(nil)
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// Feed one loudness sample (called ~30x/s while recording).
    func push(level: Float) {
        levels.removeFirst()
        levels.append(level)
    }

    // MARK: - Panel management

    private func presentPanel() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        position(panel)
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 210, height: 54),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = NSHostingView(rootView: WaveformView(overlay: self))
        return panel
    }

    /// Bottom-center of the screen the mouse is on (that's where the user works).
    private func position(_ panel: NSPanel) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let frame = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(
            x: frame.midX - size.width / 2,
            y: frame.minY + 70
        )
        panel.setFrameOrigin(origin)
    }
}
