import AVFoundation
import Combine

/// Opt-in background mode. A silent, mixable audio stream keeps Pebble running
/// so call and step alerts work while the iPhone is locked. It never plays an
/// audible sound and never interrupts other audio. Costs some iPhone battery.
final class KeepAlive: ObservableObject {
    @Published private(set) var running = false
    private var engine = AVAudioEngine()
    private var player = AVAudioPlayerNode()
    private var buffer: AVAudioPCMBuffer?
    private var wanted = false
    private var bag = Set<AnyCancellable>()

    init() {
        let center = NotificationCenter.default
        center.publisher(for: AVAudioSession.interruptionNotification).receive(on: DispatchQueue.main).sink { [weak self] note in
            guard let self, let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended, self.wanted else { return }
            self.restart()
        }.store(in: &bag)
        center.publisher(for: AVAudioSession.mediaServicesWereResetNotification).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.wanted else { return }
            self.engine = AVAudioEngine(); self.player = AVAudioPlayerNode(); self.buffer = nil
            self.restart()
        }.store(in: &bag)
        center.publisher(for: .AVAudioEngineConfigurationChange).receive(on: DispatchQueue.main).sink { [weak self] _ in
            guard let self, self.wanted else { return }
            self.restart()
        }.store(in: &bag)
    }

    func start() { wanted = true; restart() }

    func stop() {
        wanted = false
        player.stop(); engine.stop()
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        running = false
    }

    private func restart() {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            if buffer == nil {
                let format = AVAudioFormat(standardFormatWithSampleRate: 8000, channels: 1)!
                engine.attach(player)
                engine.connect(player, to: engine.mainMixerNode, format: format)
                let silence = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8000)!
                silence.frameLength = 8000 // zero-filled: one second of silence
                buffer = silence
            }
            if !engine.isRunning { try engine.start() }
            if !player.isPlaying, let buffer {
                player.scheduleBuffer(buffer, at: nil, options: .loops)
                player.play()
            }
            running = true
        } catch { running = false }
    }
}
