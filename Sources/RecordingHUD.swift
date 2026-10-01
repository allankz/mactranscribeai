import AppKit

/// Painelzinho flutuante que não rouba o foco do teclado do app da frente.
final class RecordingHUD {

    private var panel: NSPanel?
    private var titleLabel: NSTextField!
    private var timeLabel: NSTextField!
    private var meter: LevelMeterView!
    private var cancelButton: NSButton!

    var onCancel: (() -> Void)?
    var onStop: (() -> Void)?

    func showRecording(hotKeyDisplay: String) {
        build()
        titleLabel.stringValue = "Gravando…"
        timeLabel.stringValue = "0:00"
        timeLabel.isHidden = false
        meter.isHidden = false
        meter.level = 0
        cancelButton.title = "⎋ Cancelar   ·   \(hotKeyDisplay) transcreve"
        cancelButton.isHidden = false
        panel?.orderFrontRegardless()
    }

    func showTranscribing() {
        guard panel != nil else { return }
        titleLabel.stringValue = "Transcrevendo…"
        timeLabel.isHidden = true
        meter.isHidden = true
        cancelButton.title = "⎋ Cancelar"
        cancelButton.isHidden = false
    }

    func showTranslating() {
        guard panel != nil else { return }
        titleLabel.stringValue = "Traduzindo…"
        timeLabel.isHidden = true
        meter.isHidden = true
        cancelButton.title = "⎋ Cancelar"
        cancelButton.isHidden = false
    }

    func update(level: Float, elapsed: TimeInterval) {
        meter.level = CGFloat(level)
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        timeLabel.stringValue = String(format: "%d:%02d", m, s)
    }

    func hide() {
        panel?.orderOut(nil)
        panel = nil
    }

    // MARK: - Construção

    private func build() {
        guard panel == nil else { return }

        let width: CGFloat = 300
        let height: CGFloat = 92

        let p = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        p.isFloatingPanel = true
        p.level = .statusBar
        p.hidesOnDeactivate = false
        p.isOpaque = false
        p.backgroundColor = .clear
        p.hasShadow = true
        p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        p.isMovableByWindowBackground = true

        let blur = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        blur.material = .hudWindow
        blur.blendingMode = .behindWindow
        blur.state = .active
        blur.wantsLayer = true
        blur.layer?.cornerRadius = 14
        blur.layer?.masksToBounds = true
        blur.autoresizingMask = [.width, .height]
        p.contentView = blur

        let dot = NSView(frame: NSRect(x: 18, y: height - 32, width: 10, height: 10))
        dot.wantsLayer = true
        dot.layer?.backgroundColor = NSColor.systemRed.cgColor
        dot.layer?.cornerRadius = 5
        blur.addSubview(dot)
        addPulse(to: dot)

        titleLabel = label("Gravando…", size: 13, weight: .semibold)
        titleLabel.frame = NSRect(x: 36, y: height - 36, width: 160, height: 18)
        blur.addSubview(titleLabel)

        timeLabel = label("0:00", size: 12, weight: .regular)
        timeLabel.alignment = .right
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.frame = NSRect(x: width - 76, y: height - 36, width: 58, height: 18)
        blur.addSubview(timeLabel)

        meter = LevelMeterView(frame: NSRect(x: 18, y: height - 56, width: width - 36, height: 8))
        blur.addSubview(meter)

        cancelButton = NSButton(title: "Cancelar", target: self, action: #selector(cancelTapped))
        cancelButton.bezelStyle = .inline
        cancelButton.controlSize = .small
        cancelButton.font = .systemFont(ofSize: 11)
        cancelButton.frame = NSRect(x: 14, y: 12, width: width - 28, height: 20)
        blur.addSubview(cancelButton)

        if let screen = NSScreen.main {
            let f = screen.visibleFrame
            p.setFrameOrigin(NSPoint(x: f.midX - width / 2, y: f.maxY - height - 60))
        }

        panel = p
    }

    @objc private func cancelTapped() {
        onCancel?()
    }

    private func label(_ text: String, size: CGFloat, weight: NSFont.Weight) -> NSTextField {
        let l = NSTextField(labelWithString: text)
        l.font = .systemFont(ofSize: size, weight: weight)
        return l
    }

    private func addPulse(to view: NSView) {
        let a = CABasicAnimation(keyPath: "opacity")
        a.fromValue = 1.0
        a.toValue = 0.25
        a.duration = 0.7
        a.autoreverses = true
        a.repeatCount = .infinity
        view.layer?.add(a, forKey: "pulse")
    }
}

final class LevelMeterView: NSView {

    var level: CGFloat = 0 {
        didSet {
            // Suaviza para não piscar a cada amostra.
            smoothed = smoothed * 0.6 + level * 0.4
            needsDisplay = true
        }
    }

    private var smoothed: CGFloat = 0

    override func draw(_ dirtyRect: NSRect) {
        let track = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.labelColor.withAlphaComponent(0.12).setFill()
        track.fill()

        let w = max(bounds.height, bounds.width * min(1, smoothed))
        let fillRect = NSRect(x: 0, y: 0, width: w, height: bounds.height)
        let fill = NSBezierPath(roundedRect: fillRect, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        NSColor.systemRed.withAlphaComponent(0.9).setFill()
        fill.fill()
    }
}
