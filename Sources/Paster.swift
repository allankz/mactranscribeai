import AppKit
import ApplicationServices

enum Paster {

    static var hasAccessibilityPermission: Bool {
        AXIsProcessTrusted()
    }

    /// Abre o diálogo do sistema pedindo Acessibilidade (só aparece uma vez por app).
    @discardableResult
    static func requestAccessibilityPermission() -> Bool {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    static func copyToClipboard(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Devolve o foco ao app anterior e envia ⌘V.
    static func paste(_ text: String, into app: NSRunningApplication?, completion: (() -> Void)? = nil) {
        copyToClipboard(text)

        let fire = {
            let source = CGEventSource(stateID: .combinedSessionState)
            source?.setLocalEventsFilterDuringSuppressionState(
                [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
                state: .eventSuppressionStateSuppressionInterval)

            let vKey: CGKeyCode = 9 // kVK_ANSI_V
            let down = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
            down?.flags = .maskCommand
            up?.flags = .maskCommand
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
            completion?()
        }

        if let app, !app.isActive {
            app.activate()
            // Espera o app da frente realmente assumir o foco do teclado.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.18, execute: fire)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: fire)
        }
    }
}
