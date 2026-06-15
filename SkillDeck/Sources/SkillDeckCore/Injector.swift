import Foundation

public struct Injector {
    /// Derives the default text to insert for an item.
    public static func defaultInsertText(kind: ItemKind, name: String) -> String {
        switch kind {
        case .command, .builtinCommand:
            return name.hasPrefix("/") ? name : "/\(name)"
        case .skill:
            return "use the \(name) skill"
        }
    }
}

// MARK: - Accessibility & clipboard injection

import AppKit

extension Injector {
    /// True if the process is trusted for Accessibility (needed to post ⌘V).
    public static var isAccessibilityTrusted: Bool {
        AXIsProcessTrusted()
    }

    /// Prompts the user to grant Accessibility, opening the System Settings pane.
    public static func requestAccessibility() {
        // Swift 6: kAXTrustedCheckOptionPrompt (a C extern CFStringRef) is flagged as shared
        // mutable state. Use the stable string value directly to avoid the concurrency error
        // while preserving identical behaviour.
        let opts = ["AXTrustedCheckOptionPrompt": true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(opts)
    }

    /// Copies `text` to the clipboard, re-activates `target`, and posts ⌘V.
    /// Returns false (copy-only) if Accessibility isn't granted — text is still on the clipboard.
    @MainActor
    @discardableResult
    public static func inject(_ text: String, into target: NSRunningApplication?) -> Bool {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)

        guard isAccessibilityTrusted else { return false }
        target?.activate()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            postCommandV()
        }
        return true
    }

    @MainActor
    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 0x09 // 'v'
        let down = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: true)
        down?.flags = .maskCommand
        let up = CGEvent(keyboardEventSource: src, virtualKey: vKey, keyDown: false)
        up?.flags = .maskCommand
        down?.post(tap: .cgAnnotatedSessionEventTap)
        up?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
