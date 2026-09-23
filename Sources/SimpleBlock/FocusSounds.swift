import AVFoundation
import Combine
import SwiftUI

/// One focus sound: a free internet radio stream, or noise made on the fly so something plays offline.
struct FocusSound: Identifiable, Equatable {
    enum Category: String, CaseIterable { case lofi = "Lofi", jazz = "Jazz", ambient = "Ambient", noise = "Noise" }
    enum Source: Equatable { case stream(URL), noise(Noise) }

    let id: String
    let name: String
    let category: Category
    let source: Source

    /// For the error text: a stream can be unreachable, noise can only fail to start.
    var isStream: Bool { if case .stream = source { true } else { false } }

    /// The catalog, in menu order. Streams are HTTPS (no ATS exceptions), checked to play on 2026-09-23.
    static let all: [FocusSound] = [
        stream("chillhop", "Chillhop", .lofi, "https://streams.fluxfm.de/Chillhop/mp3-128/audio/"),
        stream("lofi-radio", "Lofi Radio", .lofi, "https://stream.laut.fm/lofi"),
        stream("jazz24", "Jazz24", .jazz, "https://knkx-live-a.edge.audiocdn.com/6285_128k"),
        stream("sonic-universe", "Sonic Universe", .jazz, "https://ice.somafm.com/sonicuniverse-128-mp3"),
        stream("groove-salad", "Groove Salad", .ambient, "https://ice.somafm.com/groovesalad-128-mp3"),
        stream("drone-zone", "Drone Zone", .ambient, "https://ice.somafm.com/dronezone-128-mp3"),
        FocusSound(id: "brown-noise", name: "Brown noise", category: .noise, source: .noise(.brown)),
        FocusSound(id: "pink-noise", name: "Pink noise", category: .noise, source: .noise(.pink)),
    ]

    private static func stream(_ id: String, _ name: String, _ category: Category, _ url: String) -> FocusSound {
        FocusSound(id: id, name: name, category: category, source: .stream(URL(string: url)!))
    }
}

/// Brown or pink noise, generated sample by sample, no files and no network.
enum Noise {
    case brown, pink

    /// An engine with this noise wired into its main mixer, not started yet.
    /// Stereo with a separate noise per channel, which sounds wider than mono.
    func engine() -> AVAudioEngine {
        let engine = AVAudioEngine()
        let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 2)!
        var channels = [NoiseChannel(seed: 0x9E37_79B9), NoiseChannel(seed: 0x85EB_CA6B)]
        let noise = self
        let source = AVAudioSourceNode(format: format) { _, _, frames, audio in
            for (index, buffer) in UnsafeMutableAudioBufferListPointer(audio).enumerated() {
                let samples = buffer.mData!.assumingMemoryBound(to: Float.self)
                for frame in 0..<Int(frames) { samples[frame] = channels[index % 2].next(noise) }
            }
            return noErr
        }
        engine.attach(source)
        engine.connect(source, to: engine.mainMixerNode, format: format)
        return engine
    }
}

/// Filter state for one channel. White noise comes from a xorshift, the render thread shouldn't call the system RNG.
private struct NoiseChannel {
    var seed: UInt32
    var b0: Float = 0, b1: Float = 0, b2: Float = 0, b3: Float = 0, b4: Float = 0, b5: Float = 0, b6: Float = 0

    /// Next sample, peaks well under 1 at full volume.
    mutating func next(_ noise: Noise) -> Float {
        seed ^= seed << 13
        seed ^= seed >> 17
        seed ^= seed << 5
        let white = Float(seed) / Float(UInt32.max) * 2 - 1
        switch noise {
        case .brown:
            // Leaky integrator over white noise.
            b0 = (b0 + 0.02 * white) / 1.02
            return b0 * 1.6
        case .pink:
            // Paul Kellet's refined pink filter.
            b0 = 0.99886 * b0 + white * 0.0555179
            b1 = 0.99332 * b1 + white * 0.0750759
            b2 = 0.96900 * b2 + white * 0.1538520
            b3 = 0.86650 * b3 + white * 0.3104856
            b4 = 0.55000 * b4 + white * 0.5329522
            b5 = -0.7616 * b5 - white * 0.0168980
            let pink = b0 + b1 + b2 + b3 + b4 + b5 + b6 + white * 0.5362
            b6 = white * 0.115926
            return pink * 0.05
        }
    }
}

/// Plays the chosen focus sound. One shared instance, so the popover and Settings drive the same playback.
/// Pause drops the player, so play picks a live stream up where it is now, not where it stopped.
@MainActor final class FocusSounds: ObservableObject {
    static let shared = FocusSounds()

    @Published private(set) var sound: FocusSound
    @Published private(set) var isPlaying = false
    /// The stream failed or dropped, or the noise couldn't start. Shows an error, the next play clears it.
    @Published private(set) var failed = false
    /// The slider, 0...1. Gain is its square, which feels more even than linear.
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "focusSoundVolume")
            applyVolume()
        }
    }

    private var player: AVPlayer?
    private var engine: AVAudioEngine?
    private var watch: AnyCancellable?

    private init() {
        let defaults = UserDefaults.standard
        sound = FocusSound.all.first { $0.id == defaults.string(forKey: "focusSound") } ?? FocusSound.all[0]
        volume = defaults.object(forKey: "focusSoundVolume") as? Double ?? 0.5
    }

    /// Picks a sound. While playing, playback switches to it right away.
    func select(_ sound: FocusSound) {
        guard sound != self.sound else { return }
        self.sound = sound
        failed = false
        UserDefaults.standard.set(sound.id, forKey: "focusSound")
        if isPlaying { play() }
    }

    /// Starts the selected sound, replacing whatever plays.
    func play() {
        stopPlayback()
        failed = false
        isPlaying = true
        switch sound.source {
        case .stream(let url):
            let item = AVPlayerItem(url: url)
            player = AVPlayer(playerItem: item)
            // A live stream never ends, so an end means it dropped.
            let center = NotificationCenter.default
            watch = Publishers.Merge3(
                item.publisher(for: \.status).filter { $0 == .failed }.map { _ in () },
                center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).map { _ in () },
                center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item).map { _ in () })
                .receive(on: DispatchQueue.main)
                .sink { [weak self] in self?.fail() }
        case .noise(let noise):
            engine = noise.engine()
            // The engine stops when the output device changes (AirPods connect), so start over on the new one.
            watch = NotificationCenter.default.publisher(for: .AVAudioEngineConfigurationChange, object: engine)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.play() }
        }
        applyVolume()
        player?.play()
        if let engine, (try? engine.start()) == nil { fail() }
    }

    /// Stops playback and drops the player.
    func pause() {
        stopPlayback()
        isPlaying = false
    }

    func toggle() {
        isPlaying ? pause() : play()
    }

    private func fail() {
        pause()
        failed = true
    }

    private func stopPlayback() {
        watch = nil
        player?.pause()
        player = nil
        engine?.stop()
        engine = nil
    }

    private func applyVolume() {
        let gain = Float(volume * volume)
        player?.volume = gain
        engine?.mainMixerNode.outputVolume = gain
    }
}

/// Focus sounds: a dropdown grouped by category, a round play button, a speaker and a volume slider.
/// Base size fits the popover, `scale` multiplies fonts and controls for bigger places.
struct FocusSoundsControl: View {
    @ObservedObject var sounds: FocusSounds
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Menu {
                ForEach(FocusSound.Category.allCases, id: \.self) { category in
                    Section(category.rawValue) {
                        ForEach(FocusSound.all.filter { $0.category == category }) { sound in
                            Toggle(sound.name, isOn: Binding(get: { sounds.sound == sound },
                                                             set: { _ in sounds.select(sound) }))
                        }
                    }
                }
            } label: {
                HStack {
                    Text(sounds.sound.name)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.system(size: 12 * scale, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 12 * scale).padding(.vertical, 8 * scale)
                .contentShape(Rectangle())
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8 * scale))
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)

            HStack(spacing: 12 * scale) {
                Button(action: sounds.toggle) {
                    Image(systemName: sounds.isPlaying ? "pause.fill" : "play.fill")
                        .font(.system(size: 15 * scale))
                        .foregroundStyle(.white)
                        .frame(width: 36 * scale, height: 36 * scale)
                        .background(Color.green, in: Circle())
                }
                .buttonStyle(.plain)
                .help(sounds.isPlaying ? "Pause" : "Play")
                Image(systemName: "speaker.wave.3.fill", variableValue: sounds.volume)
                    .foregroundStyle(.secondary)
                    .frame(width: 24 * scale)
                Slider(value: $sounds.volume, in: 0...1)
                    .tint(.green)
                    .controlSize(scale > 1.2 ? .extraLarge : .large)
            }

            if sounds.failed {
                Text(sounds.sound.isStream ? "Can't reach this stream" : "Can't play the noise")
                    .font(.system(size: 13 * scale))
                    .foregroundStyle(.red)
            }
        }
        .font(.system(size: 15 * scale))
    }
}
