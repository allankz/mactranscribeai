import AppKit
import AVFoundation

final class AppDelegate: NSObject, NSApplicationDelegate {

    private enum State {
        case idle, recording, transcribing, translating, reviewing
    }

    private var state: State = .idle {
        didSet { syncEscapeCapture() }
    }

    private var statusItem: NSStatusItem!
    private let recorder = Recorder()
    private let hud = RecordingHUD()
    private let review = ReviewPanel()

    /// App que estava na frente quando a gravação começou — é para lá que o texto volta.
    private var targetApp: NSRunningApplication?

    /// Observa a concessão de Acessibilidade enquanto o usuário mexe nos Ajustes.
    private var accessibilityWatcher: Timer?

    /// Upload em andamento, para o Esc poder abortar.
    private var pendingTask: URLSessionDataTask?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setUpStatusItem()
        wireCallbacks()
        applyHotKey()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            self?.warnIfHotKeyIsTaken()
        }

        if Keychain.apiKey == nil {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
                self?.showWelcome()
            }
        }
    }

    // MARK: - Fluxo principal

    private func wireCallbacks() {
        HotKeyManager.shared.onTrigger = { [weak self] in
            self?.toggle()
        }

        // Disparo acidental precisa de saída imediata: Esc aborta gravação e upload.
        HotKeyManager.shared.onEscape = { [weak self] in
            self?.abort()
        }

        recorder.onLevel = { [weak self] level, elapsed in
            self?.hud.update(level: level, elapsed: elapsed)
        }

        hud.onCancel = { [weak self] in
            self?.cancelRecording()
        }

        review.onPaste = { [weak self] text in
            guard let self else { return }
            self.state = .idle
            self.updateIcon()
            guard Paster.hasAccessibilityPermission else {
                Paster.copyToClipboard(text)
                self.showAccessibilityHelp()
                return
            }
            Paster.paste(text, into: self.targetApp)
        }

        review.onCopy = { [weak self] text in
            guard let self else { return }
            self.state = .idle
            self.updateIcon()
            Paster.copyToClipboard(text)
            self.targetApp?.activate()
        }

        review.onDiscard = { [weak self] in
            guard let self else { return }
            self.state = .idle
            self.updateIcon()
            self.targetApp?.activate()
        }
    }

    @objc private func toggle() {
        switch state {
        case .idle:
            startRecording()
        case .recording:
            finishRecording()
        case .transcribing, .translating:
            break // já está a caminho
        case .reviewing:
            review.close()
            state = .idle
            updateIcon()
        }
    }

    private func startRecording() {
        Recorder.requestMicrophoneAccess { [weak self] granted in
            guard let self else { return }
            guard granted else {
                self.showMicrophoneHelp()
                return
            }
            self.targetApp = NSWorkspace.shared.frontmostApplication
            guard self.recorder.start() else {
                self.showAlert(title: "Não consegui acessar o microfone",
                               message: "Verifique se há um microfone disponível e se o MacTranscribe tem permissão em Ajustes → Privacidade e Segurança → Microfone.")
                return
            }
            self.state = .recording
            self.updateIcon()
            self.hud.showRecording(hotKeyDisplay: Config.hotKeyDisplay)
        }
    }

    /// Esc: sai de qualquer estado ativo sem transcrever, sem colar e sem gastar API.
    private func abort() {
        pendingTask?.cancel()
        pendingTask = nil
        recorder.cancel()
        hud.hide()
        review.close()
        state = .idle
        updateIcon()
        targetApp?.activate()
    }

    /// Esc fica capturado globalmente só enquanto ele é necessário — nunca em repouso.
    private func syncEscapeCapture() {
        switch state {
        case .recording, .transcribing, .translating:
            HotKeyManager.shared.registerEscape()
        case .idle, .reviewing:
            HotKeyManager.shared.unregisterEscape()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyManager.shared.unregisterEscape()
    }

    private func cancelRecording() {
        recorder.cancel()
        hud.hide()
        state = .idle
        updateIcon()
        targetApp?.activate()
    }

    private func finishRecording() {
        guard let url = recorder.stop() else {
            hud.hide()
            state = .idle
            updateIcon()
            return
        }
        state = .transcribing
        updateIcon()
        hud.showTranscribing()

        pendingTask = Transcriber.transcribe(fileURL: url) { [weak self] result in
            guard let self else { return }
            self.pendingTask = nil
            switch result {
            case .success(let text) where text.isEmpty:
                self.hud.hide()
                self.state = .idle
                self.updateIcon()
                self.showAlert(title: "Nada foi reconhecido",
                               message: "O áudio ficou em silêncio ou muito curto.")
            case .success(let text):
                if Config.translateToEnglish {
                    self.translateThenPresent(text)   // HUD segue visível
                } else {
                    self.hud.hide()
                    self.present(text)
                }
            case .failure(let error):
                self.hud.hide()
                self.state = .reviewing
                self.updateIcon()
                self.review.show(text: error.localizedDescription, isError: true)
            }
        }
    }

    /// Uma passada de tradução, e só. Se falhar, mostra o original em vez de descartar
    /// o que a pessoa acabou de falar.
    private func translateThenPresent(_ original: String) {
        state = .translating
        updateIcon()
        hud.showTranslating()

        pendingTask = Translator.translateToEnglish(original) { [weak self] result in
            guard let self else { return }
            self.pendingTask = nil
            self.hud.hide()
            switch result {
            case .success(let english):
                self.present(english, notice: "traduzido para inglês")
            case .failure(let error):
                NSLog("MacTranscribe: tradução falhou: \(error.localizedDescription)")
                self.present(original, notice: "⚠︎ tradução falhou — texto original")
            }
        }
    }

    private func present(_ text: String, notice: String? = nil) {
        if Config.autoPaste, Paster.hasAccessibilityPermission {
            state = .idle
            updateIcon()
            Paster.paste(text, into: targetApp)
        } else {
            state = .reviewing
            updateIcon()
            review.show(text: text, notice: notice)
        }
    }

    // MARK: - Barra de menu

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateIcon()
        rebuildMenu()
    }

    private func updateIcon() {
        guard let button = statusItem.button else { return }
        let name: String
        switch state {
        case .idle:         name = "mic"
        case .recording:    name = "mic.fill"
        case .transcribing: name = "waveform"
        case .translating:  name = "character.book.closed"
        case .reviewing:    name = "text.bubble"
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "MacTranscribe")
        image?.isTemplate = state != .recording
        button.image = image
        button.contentTintColor = state == .recording ? .systemRed : nil
        rebuildMenu()   // o item "Gravar"/"Parar" acompanha o estado
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: state == .recording ? "Parar gravação" : "Gravar",
                                    action: #selector(toggle), keyEquivalent: "")
        toggleItem.target = self
        menu.addItem(toggleItem)

        let conflict = SystemHotKeys.conflict(keyCode: Config.hotKeyCode, carbonModifiers: Config.hotKeyModifiers)
        let shortcutInfo = NSMenuItem(
            title: conflict == nil
                ? "Atalho global: \(Config.hotKeyDisplay)"
                : "⚠︎ \(Config.hotKeyDisplay) está ocupado pelo macOS",
            action: conflict == nil ? nil : #selector(customHotKey),
            keyEquivalent: "")
        shortcutInfo.target = self
        shortcutInfo.isEnabled = conflict != nil
        menu.addItem(shortcutInfo)

        menu.addItem(.separator())

        var hotKeyItems: [NSMenuItem] = Config.presets.enumerated().map { index, preset in
            item(preset.display, checked: Config.matchesCurrentHotKey(preset),
                 action: #selector(pickHotKey(_:)), tag: index)
        }
        hotKeyItems.append(.separator())
        let custom = NSMenuItem(title: "Personalizar…", action: #selector(customHotKey), keyEquivalent: "")
        custom.target = self
        hotKeyItems.append(custom)
        menu.addItem(submenu("Atalho", items: hotKeyItems))

        menu.addItem(submenu("Modelo", items: Config.models.enumerated().map { index, model in
            item(model.title, checked: model.id == Config.model, action: #selector(pickModel(_:)), tag: index)
        }))

        menu.addItem(submenu("Idioma", items: Config.languages.enumerated().map { index, lang in
            item(lang.title, checked: lang.code == Config.language, action: #selector(pickLanguage(_:)), tag: index)
        }))

        let translateItem = NSMenuItem(title: "Traduzir para inglês",
                                       action: #selector(toggleTranslate), keyEquivalent: "")
        translateItem.target = self
        translateItem.state = Config.translateToEnglish ? .on : .off
        menu.addItem(translateItem)

        let autoItem = NSMenuItem(title: "Colar sem revisar", action: #selector(toggleAutoPaste), keyEquivalent: "")
        autoItem.target = self
        autoItem.state = Config.autoPaste ? .on : .off
        menu.addItem(autoItem)

        menu.addItem(.separator())

        let keyItem = NSMenuItem(title: Keychain.apiKey == nil ? "Definir chave da API…" : "Trocar chave da API…",
                                 action: #selector(setAPIKey), keyEquivalent: "")
        keyItem.target = self
        menu.addItem(keyItem)

        let vocabItem = NSMenuItem(title: "Vocabulário / contexto…", action: #selector(setVocabulary), keyEquivalent: "")
        vocabItem.target = self
        menu.addItem(vocabItem)

        let permItem = NSMenuItem(title: "Permissões…", action: #selector(showPermissions), keyEquivalent: "")
        permItem.target = self
        menu.addItem(permItem)

        menu.addItem(.separator())

        let restart = NSMenuItem(title: "Reiniciar o MacTranscribe", action: #selector(relaunch), keyEquivalent: "")
        restart.target = self
        menu.addItem(restart)

        let quit = NSMenuItem(title: "Sair do MacTranscribe", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)

        statusItem.menu = menu
    }

    private func submenu(_ title: String, items: [NSMenuItem]) -> NSMenuItem {
        let parent = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let sub = NSMenu()
        items.forEach { sub.addItem($0) }
        parent.submenu = sub
        return parent
    }

    private func item(_ title: String, checked: Bool, action: Selector, tag: Int) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: "")
        i.target = self
        i.tag = tag
        i.state = checked ? .on : .off
        return i
    }

    // MARK: - Ações do menu

    @objc private func pickHotKey(_ sender: NSMenuItem) {
        let preset = Config.presets[sender.tag]
        Config.setHotKey(code: preset.keyCode, modifiers: preset.modifiers)
        applyHotKey()
        rebuildMenu()
    }

    @objc private func customHotKey() {
        NSApp.activate(ignoringOtherApps: true)
        if let picked = HotKeyRecorder.run(current: (Config.hotKeyCode, Config.hotKeyModifiers)) {
            Config.setHotKey(code: picked.code, modifiers: picked.modifiers)
            applyHotKey()
            rebuildMenu()
        }
    }

    @objc private func pickModel(_ sender: NSMenuItem) {
        Config.model = Config.models[sender.tag].id
        rebuildMenu()
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        Config.language = Config.languages[sender.tag].code
        rebuildMenu()
    }

    @objc private func toggleTranslate() {
        Config.translateToEnglish.toggle()
        rebuildMenu()
    }

    @objc private func toggleAutoPaste() {
        Config.autoPaste.toggle()
        if Config.autoPaste, !Paster.hasAccessibilityPermission {
            Paster.requestAccessibilityPermission()
        }
        rebuildMenu()
    }

    private func applyHotKey() {
        HotKeyManager.shared.register(keyCode: Config.hotKeyCode, modifiers: Config.hotKeyModifiers)
    }

    /// RegisterEventHotKey aceita combinações que o macOS já reservou e nunca dispara.
    /// Como o retorno da API não denuncia isso, conferimos a lista do sistema no boot.
    private func warnIfHotKeyIsTaken() {
        guard let owner = SystemHotKeys.conflict(keyCode: Config.hotKeyCode,
                                                 carbonModifiers: Config.hotKeyModifiers) else { return }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "O atalho \(Config.hotKeyDisplay) está ocupado"
        alert.informativeText = """
        O macOS já usa essa combinação para \(owner), e captura a tecla antes de qualquer app — por isso o atalho não funciona aqui.

        Escolha outra combinação.
        """
        alert.addButton(withTitle: "Escolher outro atalho…")
        alert.addButton(withTitle: "Depois")
        if alert.runModal() == .alertFirstButtonReturn {
            customHotKey()
        }
    }

    @objc private func setAPIKey() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Chave da API da OpenAI"
        alert.informativeText = "Cole sua chave (começa com sk-). Ela é guardada no Keychain do macOS, não em arquivo."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")
        if Keychain.apiKey != nil {
            alert.addButton(withTitle: "Remover")
        }

        let field = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        field.placeholderString = "sk-…"
        field.stringValue = Keychain.apiKey ?? ""
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Keychain.apiKey = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        case .alertThirdButtonReturn:
            Keychain.apiKey = nil
        default:
            break
        }
        rebuildMenu()
    }

    @objc private func setVocabulary() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Vocabulário / contexto"
        alert.informativeText = "Palavras que você usa muito e o modelo costuma errar: nomes próprios, siglas, jargão. Ex.: “Allan, Supabase, MacTranscribe, MRR, deploy”."
        alert.addButton(withTitle: "Salvar")
        alert.addButton(withTitle: "Cancelar")

        let scroll = NSScrollView(frame: NSRect(x: 0, y: 0, width: 340, height: 70))
        let tv = NSTextView(frame: scroll.bounds)
        tv.string = Config.vocabularyPrompt
        tv.font = .systemFont(ofSize: 12)
        tv.isRichText = false
        scroll.documentView = tv
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        alert.accessoryView = scroll

        if alert.runModal() == .alertFirstButtonReturn {
            Config.vocabularyPrompt = tv.string.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    @objc private func showPermissions() {
        NSApp.activate(ignoringOtherApps: true)

        let mic = AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        let ax = Paster.hasAccessibilityPermission

        let alert = NSAlert()
        alert.messageText = "Permissões"
        alert.informativeText = """
        \(mic ? "✅" : "❌")  Microfone — necessário para gravar.
        \(ax ? "✅" : "❌")  Acessibilidade — necessário para colar no cursor com ⌘V.

        Sem Acessibilidade o app ainda funciona: o texto vai para a área de transferência e você cola na mão.
        \(Self.adHocWarning)
        """
        alert.addButton(withTitle: "Abrir Acessibilidade")
        alert.addButton(withTitle: "Abrir Microfone")
        alert.addButton(withTitle: "Fechar")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Paster.requestAccessibilityPermission()
            openSettings("Privacy_Accessibility")
            startAccessibilityWatch()
        case .alertSecondButtonReturn:
            openSettings("Privacy_Microphone")
        default:
            break
        }
    }

    /// Assinatura ad-hoc faz o macOS amarrar a permissão ao hash do binário: todo
    /// rebuild invalida a autorização e o sistema pergunta de novo.
    private static var adHocWarning: String {
        let mode = Bundle.main.infoDictionary?["MTSigningMode"] as? String ?? "adhoc"
        guard mode == "adhoc" else { return "" }
        return """


        ⚠︎ Este build é assinado ad-hoc. Cada ./build.sh gera um binário novo e o macOS
        esquece a autorização de Acessibilidade. Rode ./setup-signing.sh uma vez para
        resolver isso de vez.
        """
    }

    private func openSettings(_ anchor: String) {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)") {
            NSWorkspace.shared.open(url)
        }
    }

    // MARK: - Diálogos

    private func showWelcome() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Bem-vindo ao MacTranscribe"
        alert.informativeText = """
        O ícone 🎤 está na barra de menus.

        1. Configure sua chave da API da OpenAI.
        2. Aperte \(Config.hotKeyDisplay) em qualquer app para gravar.
        3. Aperte de novo para parar e transcrever.
        4. ⏎ cola no cursor, ⌘C copia, ⎋ descarta.
        """
        alert.addButton(withTitle: "Definir chave da API…")
        alert.addButton(withTitle: "Depois")
        if alert.runModal() == .alertFirstButtonReturn {
            setAPIKey()
        }
    }

    private func showMicrophoneHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Acesso ao microfone negado"
        alert.informativeText = "Ative o MacTranscribe em Ajustes do Sistema → Privacidade e Segurança → Microfone."
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Fechar")
        if alert.runModal() == .alertFirstButtonReturn {
            openSettings("Privacy_Microphone")
        }
    }

    private func showAccessibilityHelp() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Texto copiado — falta uma permissão para colar sozinho"
        alert.informativeText = """
        O texto já está na área de transferência: é só dar ⌘V.

        Para o MacTranscribe colar automaticamente no cursor, autorize-o em Ajustes do Sistema → Privacidade e Segurança → Acessibilidade.
        """
        alert.addButton(withTitle: "Abrir Ajustes")
        alert.addButton(withTitle: "Fechar")
        if alert.runModal() == .alertFirstButtonReturn {
            Paster.requestAccessibilityPermission()
            openSettings("Privacy_Accessibility")
            startAccessibilityWatch()
        }
    }

    // MARK: - Acessibilidade concedida em tempo de execução

    /// O TCC responde ao processo já em execução com a resposta antiga, então depois de
    /// conceder a permissão o app precisa reiniciar para de fato conseguir postar ⌘V.
    private func startAccessibilityWatch() {
        guard accessibilityWatcher == nil, !Paster.hasAccessibilityPermission else { return }
        accessibilityWatcher = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            guard Paster.hasAccessibilityPermission else { return }
            timer.invalidate()
            self?.accessibilityWatcher = nil
            self?.offerRelaunch()
        }
    }

    private func offerRelaunch() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Permissão concedida ✅"
        alert.informativeText = "O MacTranscribe precisa reiniciar para começar a usar a Acessibilidade."
        alert.addButton(withTitle: "Reiniciar agora")
        alert.addButton(withTitle: "Depois")
        if alert.runModal() == .alertFirstButtonReturn { relaunch() }
    }

    @objc private func relaunch() {
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config) { _, _ in
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    private func showAlert(title: String, message: String) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
