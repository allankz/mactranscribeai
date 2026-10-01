import Carbon.HIToolbox
import Foundation

/// Atalho global via Carbon. Diferente de um NSEvent global monitor, o
/// RegisterEventHotKey não exige permissão de Acessibilidade.
final class HotKeyManager {

    static let shared = HotKeyManager()

    var onTrigger: (() -> Void)?

    /// Esc só fica registrado enquanto há uma gravação em curso.
    var onEscape: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var escapeRef: EventHotKeyRef?
    private var handlerInstalled = false

    private enum ID {
        static let main: UInt32 = 1
        static let escape: UInt32 = 2
    }

    private(set) var isRegistered = false

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32) -> Bool {
        unregister()

        installHandlerIfNeeded()

        let id = EventHotKeyID(signature: OSType(0x4D544B59), id: ID.main) // 'MTKY'
        let status = RegisterEventHotKey(keyCode, modifiers, id, GetApplicationEventTarget(), 0, &hotKeyRef)
        isRegistered = (status == noErr)
        if !isRegistered {
            NSLog("MacTranscribe: RegisterEventHotKey falhou com status \(status)")
        }
        return isRegistered
    }

    /// Captura Esc globalmente. É deliberadamente temporário: enquanto ativo, Esc não
    /// chega em mais nenhum app, então todo caminho que sai de "gravando" precisa soltar.
    func registerEscape() {
        guard escapeRef == nil else { return }
        installHandlerIfNeeded()
        let id = EventHotKeyID(signature: OSType(0x4D544B59), id: ID.escape)
        RegisterEventHotKey(UInt32(kVK_Escape), 0, id, GetApplicationEventTarget(), 0, &escapeRef)
    }

    private func installHandlerIfNeeded() {
        guard !handlerInstalled else { return }
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                 eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), hotKeyEventHandler, 1, &spec, nil, nil)
        handlerInstalled = true
    }

    func unregisterEscape() {
        if let ref = escapeRef {
            UnregisterEventHotKey(ref)
            escapeRef = nil
        }
    }

    func unregister() {
        if let ref = hotKeyRef {
            UnregisterEventHotKey(ref)
            hotKeyRef = nil
            isRegistered = false
        }
    }
}

private let hotKeyEventHandler: EventHandlerUPP = { _, event, _ in
    var hotKeyID = EventHotKeyID()
    GetEventParameter(event, EventParamName(kEventParamDirectObject),
                      EventParamType(typeEventHotKeyID), nil,
                      MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    let id = hotKeyID.id

    DispatchQueue.main.async {
        switch id {
        case 1: HotKeyManager.shared.onTrigger?()
        case 2: HotKeyManager.shared.onEscape?()
        default: break
        }
    }
    return noErr
}
