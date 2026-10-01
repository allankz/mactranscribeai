import AppKit

/// Janela de revisão: mostra a transcrição, deixa editar e então colar/copiar.
final class ReviewPanel: NSObject, NSTextViewDelegate {

    private var panel: NSPanel?
    private var textView: NSTextView!
    private var hintLabel: NSTextField!
    private var pasteButton: NSButton!

    var onPaste: ((String) -> Void)?
    var onCopy: ((String) -> Void)?
    var onDiscard: (() -> Void)?

    var isVisible: Bool { panel?.isVisible ?? false }

    func show(text: String, isError: Bool = false, notice: String? = nil) {
        build()
        textView.string = text
        textView.textColor = isError ? .systemRed : .labelColor
        textView.font = .systemFont(ofSize: isError ? 12 : 14)
        textView.isEditable = !isError
        pasteButton.isEnabled = !isError
        let keys = isError
            ? "⎋ Fechar"
            : "⏎ Colar   ·   ⌘C Copiar   ·   ⌥⏎ Nova linha   ·   ⎋ Descartar"
        hintLabel.stringValue = notice.map { "\($0)   ·   \(keys)" } ?? keys

        fitHeight()
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel?.makeFirstResponder(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))
    }

    func close() {
        panel?.orderOut(nil)
    }

    // MARK: - Ações

    @objc private func pasteTapped() {
        let text = textView.string
        close()
        onPaste?(text)
    }

    @objc private func copyTapped() {
        let text = textView.string
        close()
        onCopy?(text)
    }

    @objc private func discardTapped() {
        close()
        onDiscard?()
    }

    // MARK: - NSTextViewDelegate

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
        switch commandSelector {
        case #selector(NSResponder.insertNewline(_:)):
            pasteTapped()
            return true
        case #selector(NSResponder.insertNewlineIgnoringFieldEditor(_:)):
            textView.insertText("\n", replacementRange: textView.selectedRange())
            return true
        case #selector(NSResponder.cancelOperation(_:)):
            discardTapped()
            return true
        default:
            return false
        }
    }

    func textDidChange(_ notification: Notification) {
        fitHeight()
    }

    // MARK: - Construção

    private let width: CGFloat = 560
    private let chromeHeight: CGFloat = 74

    private func build() {
        guard panel == nil else { return }

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: 200),
                        styleMask: [.titled, .fullSizeContentView, .utilityWindow],
                        backing: .buffered,
                        defer: false)
        p.titlebarAppearsTransparent = true
        p.titleVisibility = .hidden
        p.isFloatingPanel = true
        p.level = .floating
        p.hidesOnDeactivate = false
        p.isMovableByWindowBackground = true
        p.becomesKeyOnlyIfNeeded = false
        p.standardWindowButton(.miniaturizeButton)?.isHidden = true
        p.standardWindowButton(.zoomButton)?.isHidden = true
        p.standardWindowButton(.closeButton)?.isHidden = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let blur = NSVisualEffectView()
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        p.contentView = blur

        let scroll = NSScrollView()
        scroll.hasVerticalScroller = true
        scroll.drawsBackground = false
        scroll.autohidesScrollers = true
        scroll.translatesAutoresizingMaskIntoConstraints = false

        let tv = NSTextView()
        tv.delegate = self
        tv.isRichText = false
        tv.drawsBackground = false
        tv.font = .systemFont(ofSize: 14)
        tv.textContainerInset = NSSize(width: 6, height: 8)
        tv.isVerticallyResizable = true
        tv.isHorizontallyResizable = false
        tv.autoresizingMask = [.width]
        tv.textContainer?.widthTracksTextView = true
        tv.isAutomaticQuoteSubstitutionEnabled = false
        tv.isAutomaticDashSubstitutionEnabled = false
        tv.isAutomaticTextReplacementEnabled = false
        scroll.documentView = tv
        textView = tv

        hintLabel = NSTextField(labelWithString: "")
        hintLabel.font = .systemFont(ofSize: 11)
        hintLabel.textColor = .tertiaryLabelColor
        hintLabel.translatesAutoresizingMaskIntoConstraints = false

        pasteButton = NSButton(title: "Colar", target: self, action: #selector(pasteTapped))
        pasteButton.bezelStyle = .rounded
        pasteButton.keyEquivalent = "\r"   // botão azul padrão
        pasteButton.translatesAutoresizingMaskIntoConstraints = false

        let copyButton = NSButton(title: "Copiar", target: self, action: #selector(copyTapped))
        copyButton.bezelStyle = .rounded
        copyButton.keyEquivalent = "c"
        copyButton.keyEquivalentModifierMask = [.command]
        copyButton.translatesAutoresizingMaskIntoConstraints = false

        let discardButton = NSButton(title: "Descartar", target: self, action: #selector(discardTapped))
        discardButton.bezelStyle = .rounded
        discardButton.keyEquivalent = "\u{1b}"
        discardButton.translatesAutoresizingMaskIntoConstraints = false

        blur.addSubview(scroll)
        blur.addSubview(hintLabel)
        blur.addSubview(discardButton)
        blur.addSubview(copyButton)
        blur.addSubview(pasteButton)

        NSLayoutConstraint.activate([
            scroll.topAnchor.constraint(equalTo: blur.topAnchor, constant: 26),
            scroll.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            scroll.bottomAnchor.constraint(equalTo: pasteButton.topAnchor, constant: -10),

            pasteButton.trailingAnchor.constraint(equalTo: blur.trailingAnchor, constant: -16),
            pasteButton.bottomAnchor.constraint(equalTo: blur.bottomAnchor, constant: -14),
            copyButton.trailingAnchor.constraint(equalTo: pasteButton.leadingAnchor, constant: -8),
            copyButton.centerYAnchor.constraint(equalTo: pasteButton.centerYAnchor),
            discardButton.trailingAnchor.constraint(equalTo: copyButton.leadingAnchor, constant: -8),
            discardButton.centerYAnchor.constraint(equalTo: pasteButton.centerYAnchor),

            hintLabel.leadingAnchor.constraint(equalTo: blur.leadingAnchor, constant: 18),
            hintLabel.centerYAnchor.constraint(equalTo: pasteButton.centerYAnchor),
        ])

        panel = p
    }

    /// Altura acompanha o texto, entre 3 e 14 linhas.
    private func fitHeight() {
        guard let panel, let lm = textView.layoutManager, let tc = textView.textContainer else { return }
        lm.ensureLayout(for: tc)
        let textHeight = lm.usedRect(for: tc).height + 24
        let height = min(max(textHeight + chromeHeight, 150), 460)

        var frame = panel.frame
        let deltaTop = height - frame.height
        frame.size.height = height
        frame.origin.y -= deltaTop

        if !panel.isVisible, let screen = NSScreen.main {
            let vf = screen.visibleFrame
            frame.size.width = width
            frame.origin.x = vf.midX - width / 2
            frame.origin.y = vf.maxY - height - 120
        }
        panel.setFrame(frame, display: true, animate: panel.isVisible)
    }
}
