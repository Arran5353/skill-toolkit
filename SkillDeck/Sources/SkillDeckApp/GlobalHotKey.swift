import Carbon.HIToolbox
import AppKit

/// Registers a single system-wide hot key via Carbon (no Accessibility permission required).
/// Calls `onFire` on the main thread when pressed. Call register() once; it stays alive for app lifetime.
final class GlobalHotKey {
    private var ref: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private let onFire: () -> Void
    @MainActor private static var shared: GlobalHotKey?   // keep alive for the C callback

    init(onFire: @escaping () -> Void) { self.onFire = onFire }

    /// keyCode: Carbon virtual key (kVK_ANSI_K = 0x28). modifiers: Carbon mask
    /// (cmdKey | optionKey). Default = ⌥⌘K.
    @MainActor
    func register(keyCode: UInt32 = 0x28,   // kVK_ANSI_K
                  modifiers: UInt32 = UInt32(cmdKey | optionKey)) {
        GlobalHotKey.shared = self
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: OSType(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ -> OSStatus in
            // dispatch to the shared instance on the main thread
            DispatchQueue.main.async { GlobalHotKey.shared?.onFire() }
            return noErr
        }, 1, &eventType, nil, &handler)

        let hotKeyID = EventHotKeyID(signature: OSType(0x534B4443 /* 'SKDC' */), id: 1)
        RegisterEventHotKey(keyCode, modifiers, hotKeyID,
                            GetApplicationEventTarget(), 0, &ref)
    }

    func unregister() {
        if let ref { UnregisterEventHotKey(ref); self.ref = nil }
        if let handler { RemoveEventHandler(handler); self.handler = nil }
    }
    deinit { unregister() }
}
