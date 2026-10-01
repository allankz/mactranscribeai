import AVFoundation
import Foundation

final class Recorder: NSObject {

    private var recorder: AVAudioRecorder?
    private var meterTimer: Timer?
    private(set) var fileURL: URL?
    private(set) var startedAt: Date?

    /// Chamado ~20x/s com (nível 0...1, segundos gravados).
    var onLevel: ((Float, TimeInterval) -> Void)?

    var isRecording: Bool { recorder?.isRecording ?? false }

    static func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                DispatchQueue.main.async { completion(granted) }
            }
        default:
            completion(false)
        }
    }

    @discardableResult
    func start() -> Bool {
        stopTimer()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("mactranscribe-\(UUID().uuidString).m4a")

        // 16 kHz mono AAC: o suficiente para fala e mantém o upload pequeno.
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16_000.0,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]

        do {
            let rec = try AVAudioRecorder(url: url, settings: settings)
            rec.isMeteringEnabled = true
            guard rec.record() else { return false }
            recorder = rec
            fileURL = url
            startedAt = Date()
        } catch {
            NSLog("MacTranscribe: falha ao iniciar gravação: \(error)")
            return false
        }

        meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let rec = self.recorder else { return }
            rec.updateMeters()
            let db = rec.averagePower(forChannel: 0)          // ~-60 (silêncio) a 0 (pico)
            let level = max(0, min(1, (db + 55) / 55))
            self.onLevel?(level, rec.currentTime)
        }
        return true
    }

    /// Encerra e devolve o arquivo, ou nil se foi curto demais para valer a pena.
    func stop() -> URL? {
        stopTimer()
        guard let rec = recorder else { return nil }
        let duration = rec.currentTime
        rec.stop()
        recorder = nil
        let url = fileURL
        fileURL = nil
        guard duration >= 0.35, let url else {
            if let url { try? FileManager.default.removeItem(at: url) }
            return nil
        }
        return url
    }

    func cancel() {
        stopTimer()
        recorder?.stop()
        recorder = nil
        if let url = fileURL { try? FileManager.default.removeItem(at: url) }
        fileURL = nil
    }

    private func stopTimer() {
        meterTimer?.invalidate()
        meterTimer = nil
    }
}
