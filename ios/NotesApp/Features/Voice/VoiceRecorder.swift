import Foundation
import AVFoundation

/// Hold-to-talk recorder. Writes M4A to a temp file, exposes the raw data on stop.
final class VoiceRecorder: NSObject, ObservableObject {
    @Published var isRecording = false
    @Published var level: Float = 0

    private var recorder: AVAudioRecorder?
    private var tempURL: URL?
    private var meterTimer: Timer?

    func start() throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker])
        try session.setActive(true)

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-\(UUID().uuidString).m4a")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatMPEG4AAC),
            AVSampleRateKey: 16000,
            AVNumberOfChannelsKey: 1,
            AVEncoderAudioQualityKey: AVAudioQuality.medium.rawValue
        ]
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.isMeteringEnabled = true
        recorder.record()
        self.recorder = recorder
        self.tempURL = url
        self.isRecording = true
        self.meterTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            guard let self, let r = self.recorder else { return }
            r.updateMeters()
            let db = r.averagePower(forChannel: 0)
            self.level = max(0, 1 + db / 60) // -60 dB floor
        }
    }

    /// Stops recording and returns the captured audio as Data.
    func stop() -> Data? {
        recorder?.stop()
        recorder = nil
        meterTimer?.invalidate()
        meterTimer = nil
        isRecording = false
        level = 0
        try? AVAudioSession.sharedInstance().setActive(false)
        guard let url = tempURL else { return nil }
        let data = try? Data(contentsOf: url)
        try? FileManager.default.removeItem(at: url)
        tempURL = nil
        return data
    }
}
