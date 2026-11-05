import Carbon.HIToolbox
import Foundation

/// ⌃⌥⌘K, which starts or stops Auto from any app (spec 018 FR-009). A Carbon hot key needs no Accessibility
/// permission. The binding is fixed in this version.
@MainActor
final class GlobalHotKey {
    private(set) var isRegistered = false
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var action: (@MainActor () -> Void)?

    /// Returns whether macOS accepted the binding.
    func register(action: @escaping @MainActor () -> Void) -> Bool {
        unregister()
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let installed = InstallEventHandler(
            GetApplicationEventTarget(),
            { _, _, userData in
                guard let userData else { return noErr }
                // Carbon delivers hot-key events on the main thread.
                MainActor.assumeIsolated {
                    Unmanaged<GlobalHotKey>.fromOpaque(userData).takeUnretainedValue().action?()
                }
                return noErr
            },
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler)
        guard installed == noErr else {
            unregister()
            return false
        }
        let identifier = EventHotKeyID(signature: OSType(0x434C_4944), id: 1) // 'CLID'
        let registered = RegisterEventHotKey(UInt32(kVK_ANSI_K), UInt32(controlKey | optionKey | cmdKey),
                                             identifier, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = registered == noErr
        if !isRegistered { unregister() }
        return isRegistered
    }

    func unregister() {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        hotKeyRef = nil
        eventHandler = nil
        action = nil
        isRegistered = false
    }
}
