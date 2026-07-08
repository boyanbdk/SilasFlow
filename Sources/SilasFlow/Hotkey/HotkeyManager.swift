import Carbon.HIToolbox
import Foundation

/// Push-to-talk global hotkey via Carbon RegisterEventHotKey:
/// key-down starts recording, key-up stops it.
/// This is the one Carbon API with no modern replacement (per Apple DTS);
/// it requires NO Accessibility or Input Monitoring permission because the
/// system only tells us about our exact registered combo.
final class HotkeyManager {
    struct Combo: Identifiable, Equatable {
        let id: String
        let label: String
        let keyCode: UInt32
        let carbonModifiers: UInt32
    }

    static let presets: [Combo] = [
        Combo(id: "opt-space", label: "⌥ Space", keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(optionKey)),
        Combo(id: "ctrl-opt-space", label: "⌃⌥ Space", keyCode: UInt32(kVK_Space), carbonModifiers: UInt32(controlKey | optionKey)),
        Combo(id: "opt-cmd-d", label: "⌥⌘ D", keyCode: UInt32(kVK_ANSI_D), carbonModifiers: UInt32(optionKey | cmdKey)),
        Combo(id: "opt-grave", label: "⌥ `", keyCode: UInt32(kVK_ANSI_Grave), carbonModifiers: UInt32(optionKey)),
    ]

    var onPressDown: (() -> Void)?
    var onPressUp: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let signature: OSType = 0x53464C57 // 'SFLW'

    /// Registers (or re-registers) the global hotkey.
    func activate(combo: Combo) {
        deactivate()
        installHandlerIfNeeded()

        let hotKeyID = EventHotKeyID(signature: signature, id: 1)
        let status = RegisterEventHotKey(
            combo.keyCode,
            combo.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        if status != noErr {
            Log.app.error("RegisterEventHotKey failed: \(status, privacy: .public)")
        } else {
            Log.app.info("Hotkey registered: \(combo.label, privacy: .public)")
        }
    }

    func deactivate() {
        if let hotKeyRef {
            UnregisterEventHotKey(hotKeyRef)
            self.hotKeyRef = nil
        }
    }

    private func installHandlerIfNeeded() {
        guard handlerRef == nil else { return }
        var eventTypes = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(
            GetApplicationEventTarget(),
            { _, eventRef, userData -> OSStatus in
                guard let eventRef, let userData else { return OSStatus(eventNotHandledErr) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                return manager.handle(eventRef)
            },
            eventTypes.count,
            &eventTypes,
            selfPtr,
            &handlerRef
        )
    }

    private func handle(_ eventRef: EventRef) -> OSStatus {
        var hotKeyID = EventHotKeyID()
        let status = GetEventParameter(
            eventRef,
            EventParamName(kEventParamDirectObject),
            EventParamType(typeEventHotKeyID),
            nil,
            MemoryLayout<EventHotKeyID>.size,
            nil,
            &hotKeyID
        )
        guard status == noErr, hotKeyID.signature == signature else {
            return OSStatus(eventNotHandledErr)
        }
        switch GetEventKind(eventRef) {
        case UInt32(kEventHotKeyPressed):
            onPressDown?()
        case UInt32(kEventHotKeyReleased):
            onPressUp?()
        default:
            return OSStatus(eventNotHandledErr)
        }
        return noErr
    }
}
