import AppKit
import Carbon.HIToolbox

/// RegisterEventHotKey devolve noErr mesmo quando o macOS já é dono da combinação —
/// o sistema simplesmente engole a tecla antes de ela chegar no app. Como não dá para
/// detectar isso pelo retorno da API, conferimos direto na lista de atalhos do sistema.
enum SystemHotKeys {

    private static let relevantMask: UInt = 0x20000 | 0x40000 | 0x80000 | 0x100000

    static func cocoaFlags(fromCarbon mods: UInt32) -> UInt {
        var f: UInt = 0
        if mods & UInt32(shiftKey)   != 0 { f |= 0x20000 }
        if mods & UInt32(controlKey) != 0 { f |= 0x40000 }
        if mods & UInt32(optionKey)  != 0 { f |= 0x80000 }
        if mods & UInt32(cmdKey)     != 0 { f |= 0x100000 }
        return f
    }

    static func carbonFlags(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var m: UInt32 = 0
        if flags.contains(.shift)   { m |= UInt32(shiftKey) }
        if flags.contains(.control) { m |= UInt32(controlKey) }
        if flags.contains(.option)  { m |= UInt32(optionKey) }
        if flags.contains(.command) { m |= UInt32(cmdKey) }
        return m
    }

    /// Nome legível do atalho do sistema que colide, ou nil se estiver livre.
    static func conflict(keyCode: UInt32, carbonModifiers: UInt32) -> String? {
        guard
            let defaults = UserDefaults(suiteName: "com.apple.symbolichotkeys"),
            let all = defaults.dictionary(forKey: "AppleSymbolicHotKeys")
        else { return nil }

        let target = cocoaFlags(fromCarbon: carbonModifiers)

        for (rawID, rawEntry) in all {
            guard
                let entry = rawEntry as? [String: Any],
                (entry["enabled"] as? Bool) == true,
                let value = entry["value"] as? [String: Any],
                let params = value["parameters"] as? [Any],
                params.count >= 3,
                let code = params[1] as? Int,
                let mods = params[2] as? Int,
                code >= 0, code < 0xFFFF
            else { continue }

            if UInt32(code) == keyCode && (UInt(mods) & relevantMask) == target {
                return names[rawID] ?? "atalho do sistema nº \(rawID)"
            }
        }
        return nil
    }

    /// Os IDs que mais colidem na prática. O resto cai no texto genérico.
    private static let names: [String: String] = [
        "60": "trocar para a fonte de entrada anterior",
        "61": "trocar para a próxima fonte de entrada",
        "64": "Spotlight",
        "65": "janela de busca do Finder",
        "32": "Mission Control",
        "33": "Mission Control (janelas do app)",
        "36": "mostrar a Mesa",
        "175": "Central de Notificações",
        "179": "Central de Controle",
        "184": "captura de tela",
        "28": "captura de tela (tela inteira)",
        "30": "captura de tela (seleção)",
        "162": "Launchpad",
        "52": "Dock ocultar/mostrar",
    ]
}

/// Nomes das teclas para exibição.
enum KeyName {

    private static let special: [UInt32: String] = [
        49: "Space", 36: "↩", 48: "⇥", 51: "⌫", 53: "⎋", 117: "⌦",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "↖", 119: "↘", 116: "⇞", 121: "⇟",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15",
    ]

    static func isFunctionKey(_ code: UInt32) -> Bool {
        [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111, 105, 107, 113].contains(code)
    }

    static func display(keyCode: UInt32, characters: String?) -> String {
        if let s = special[keyCode] { return s }
        if let c = characters, !c.isEmpty, c != " " { return c.uppercased() }
        return "tecla \(keyCode)"
    }

    static func display(keyCode: UInt32, carbonModifiers: UInt32, characters: String? = nil) -> String {
        var s = ""
        if carbonModifiers & UInt32(controlKey) != 0 { s += "⌃" }
        if carbonModifiers & UInt32(optionKey)  != 0 { s += "⌥" }
        if carbonModifiers & UInt32(shiftKey)   != 0 { s += "⇧" }
        if carbonModifiers & UInt32(cmdKey)     != 0 { s += "⌘" }
        return s + display(keyCode: keyCode, characters: characters)
    }
}
