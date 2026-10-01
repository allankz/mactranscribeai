import Foundation
import Carbon.HIToolbox

struct HotKeyPreset {
    let display: String
    let keyCode: UInt32
    let modifiers: UInt32
}

enum Config {

    /// Presets já conferidos contra a lista de atalhos do sistema.
    /// ⌃⌥Space foi removido de propósito: é do macOS (trocar fonte de entrada).
    static let presets: [HotKeyPreset] = [
        HotKeyPreset(display: "⌥Space",  keyCode: UInt32(kVK_Space),  modifiers: UInt32(optionKey)),
        HotKeyPreset(display: "⌃⌥D",     keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(display: "⌃⌥⌘Space", keyCode: UInt32(kVK_Space), modifiers: UInt32(controlKey | optionKey | cmdKey)),
        HotKeyPreset(display: "⌃⌥V",     keyCode: UInt32(kVK_ANSI_V), modifiers: UInt32(controlKey | optionKey)),
        HotKeyPreset(display: "F13",     keyCode: UInt32(kVK_F13),    modifiers: 0),
    ]

    struct ModelOption {
        let id: String
        let title: String
    }

    static let models: [ModelOption] = [
        ModelOption(id: "gpt-4o-transcribe",      title: "gpt-4o-transcribe (melhor)"),
        ModelOption(id: "gpt-4o-mini-transcribe", title: "gpt-4o-mini-transcribe (barato)"),
        ModelOption(id: "whisper-1",              title: "whisper-1 (clássico)"),
    ]

    struct LanguageOption {
        let code: String
        let title: String
    }

    static let languages: [LanguageOption] = [
        LanguageOption(code: "pt", title: "Português"),
        LanguageOption(code: "en", title: "Inglês"),
        LanguageOption(code: "es", title: "Espanhol"),
        LanguageOption(code: "",   title: "Detectar automaticamente"),
    ]

    private static let d = UserDefaults.standard

    // MARK: - Atalho global (qualquer combinação, não só presets)

    static var hotKeyCode: UInt32 {
        get { UInt32(d.object(forKey: "hotKeyCode") as? Int ?? Int(kVK_Space)) }
        set { d.set(Int(newValue), forKey: "hotKeyCode") }
    }

    static var hotKeyModifiers: UInt32 {
        get { UInt32(d.object(forKey: "hotKeyModifiers") as? Int ?? optionKey) }
        set { d.set(Int(newValue), forKey: "hotKeyModifiers") }
    }

    static var hotKeyDisplay: String {
        KeyName.display(keyCode: hotKeyCode, carbonModifiers: hotKeyModifiers)
    }

    static func setHotKey(code: UInt32, modifiers: UInt32) {
        hotKeyCode = code
        hotKeyModifiers = modifiers
    }

    static func matchesCurrentHotKey(_ preset: HotKeyPreset) -> Bool {
        preset.keyCode == hotKeyCode && preset.modifiers == hotKeyModifiers
    }

    // MARK: - Transcrição

    static var model: String {
        get { d.string(forKey: "model") ?? "gpt-4o-transcribe" }
        set { d.set(newValue, forKey: "model") }
    }

    static var language: String {
        get { d.object(forKey: "language") as? String ?? "pt" }
        set { d.set(newValue, forKey: "language") }
    }

    /// Texto de contexto enviado ao modelo para enviesar vocabulário (nomes, jargão, siglas).
    static var vocabularyPrompt: String {
        get { d.string(forKey: "vocabularyPrompt") ?? "" }
        set { d.set(newValue, forKey: "vocabularyPrompt") }
    }

    /// Traduz a transcrição para inglês antes de mostrar/colar (uma chamada extra).
    static var translateToEnglish: Bool {
        get { d.bool(forKey: "translateToEnglish") }
        set { d.set(newValue, forKey: "translateToEnglish") }
    }

    /// Modelo usado só na tradução. Trocável sem recompilar:
    ///   defaults write com.allan.mactranscribe translationModel gpt-4.1-mini
    static var translationModel: String {
        get { d.string(forKey: "translationModel") ?? "gpt-4o-mini" }
        set { d.set(newValue, forKey: "translationModel") }
    }

    /// Cola direto sem mostrar a janela de revisão.
    static var autoPaste: Bool {
        get { d.bool(forKey: "autoPaste") }
        set { d.set(newValue, forKey: "autoPaste") }
    }
}
