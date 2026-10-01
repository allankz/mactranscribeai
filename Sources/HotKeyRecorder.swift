import AppKit
import Carbon.HIToolbox

/// Diálogo "aperte a combinação desejada". Captura as teclas com um monitor local,
/// que roda antes do processamento de key equivalents da janela — por isso pega até
/// combinações com ⌘ sem esbarrar nos botões do alerta.
enum HotKeyRecorder {

    /// Devolve (keyCode, modifiers) escolhidos, ou nil se cancelado.
    static func run(current: (code: UInt32, modifiers: UInt32)) -> (code: UInt32, modifiers: UInt32)? {

        var picked: (code: UInt32, modifiers: UInt32)? = nil

        let alert = NSAlert()
        alert.messageText = "Definir atalho global"
        alert.informativeText = "Aperte a combinação que você quer usar para gravar.\nUse pelo menos um modificador (⌃ ⌥ ⇧ ⌘), ou uma tecla F."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")
        alert.buttons[0].isEnabled = false

        let box = NSView(frame: NSRect(x: 0, y: 0, width: 340, height: 74))

        let combo = NSTextField(labelWithString: KeyName.display(keyCode: current.code,
                                                                 carbonModifiers: current.modifiers))
        combo.font = .systemFont(ofSize: 26, weight: .medium)
        combo.alignment = .center
        combo.frame = NSRect(x: 0, y: 34, width: 340, height: 36)
        box.addSubview(combo)

        let status = NSTextField(labelWithString: "atalho atual")
        status.font = .systemFont(ofSize: 11)
        status.textColor = .secondaryLabelColor
        status.alignment = .center
        status.frame = NSRect(x: 0, y: 8, width: 340, height: 20)
        status.maximumNumberOfLines = 2
        box.addSubview(status)

        alert.accessoryView = box

        let monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { event in

            if event.type == .flagsChanged {
                let mods = SystemHotKeys.carbonFlags(from: event.modifierFlags)
                if mods != 0 {
                    combo.stringValue = KeyName.display(keyCode: 0xFFFF, carbonModifiers: mods, characters: "…")
                        .replacingOccurrences(of: "tecla 65535", with: "…")
                    status.stringValue = "continue…"
                }
                return nil
            }

            let code = UInt32(event.keyCode)
            let mods = SystemHotKeys.carbonFlags(from: event.modifierFlags)

            // Sem modificador, só teclas F fazem sentido como atalho global.
            guard mods != 0 || KeyName.isFunctionKey(code) else {
                // Deixa ↩ e ⎋ passarem para os botões Salvar/Cancelar.
                if code == 36 || code == 53 { return event }
                status.stringValue = "Precisa de pelo menos um modificador (⌃ ⌥ ⇧ ⌘)."
                status.textColor = .systemOrange
                return nil
            }

            let display = KeyName.display(keyCode: code, carbonModifiers: mods,
                                          characters: event.charactersIgnoringModifiers)
            combo.stringValue = display

            if let owner = SystemHotKeys.conflict(keyCode: code, carbonModifiers: mods) {
                status.stringValue = "⚠︎ Já usado pelo macOS (\(owner)). O sistema captura antes do app — escolha outra."
                status.textColor = .systemRed
                alert.buttons[0].isEnabled = false
                picked = nil
            } else {
                status.stringValue = "✓ Livre — clique em Salvar."
                status.textColor = .systemGreen
                alert.buttons[0].isEnabled = true
                picked = (code, mods)
            }
            return nil
        }

        defer {
            if let monitor { NSEvent.removeMonitor(monitor) }
        }

        return alert.runModal() == .alertFirstButtonReturn ? picked : nil
    }
}
