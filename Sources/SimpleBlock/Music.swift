import AVFoundation
import Combine
import SimpleBlockCore
import SwiftUI

/// Plays music: the built-in Lofi Jazz mix and audio files added in Settings. One shared instance, so the popover
/// and Settings drive the same playback. Saved in UserDefaults: `music` (JSON MusicLibrary), `musicTrack`, `musicVolume`.
@MainActor final class Music: ObservableObject {
    static let shared = Music()

    /// Where the tracks live: ~/Library/Application Support/SimpleBlock/Music.
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SimpleBlock/Music", isDirectory: true)
    /// Lorenzo Gambino's "Lofi Jazz" on the Internet Archive: one 8 h mix, 471 MB, CC0.
    static let lofiJazzURL = URL(string: "https://archive.org/download/lofi-jazz/Lofi%20Jazz.mp3")!

    @Published var library: MusicLibrary {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(library), forKey: "music") }
    }
    @Published private(set) var track: Track
    @Published private(set) var isPlaying = false
    /// The track couldn't play (file gone, no network for the mix). The next play clears it.
    @Published private(set) var failed = false
    /// The slider, 0...1. Gain is its square, which feels more even than linear.
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "musicVolume")
            player?.volume = Float(volume * volume)
        }
    }
    /// Lofi Jazz download progress, 0...1, while it runs.
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadFailed = false

    private var player: AVPlayer?
    private var watch: AnyCancellable?
    private var download: URLSessionDownloadTask?
    private var downloadWatch: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        let library = defaults.data(forKey: "music").flatMap { try? JSONDecoder().decode(MusicLibrary.self, from: $0) }
            ?? .standard
        self.library = library
        track = library.tracks.first { $0.id == defaults.string(forKey: "musicTrack") } ?? .lofiJazz
        volume = defaults.object(forKey: "musicVolume") as? Double ?? 0.5
    }

    // MARK: Playback

    /// Plays a track from the start, replacing whatever plays.
    func play(_ track: Track) {
        self.track = track
        UserDefaults.standard.set(track.id, forKey: "musicTrack")
        start()
    }

    /// Pause keeps the spot, play goes on from it.
    func toggle() {
        if isPlaying {
            player?.pause()
            isPlaying = false
        } else if let player {
            player.play()
            isPlaying = true
        } else {
            start()
        }
    }

    private func start() {
        stop()
        failed = false
        let item = AVPlayerItem(url: source(track))
        let player = AVPlayer(playerItem: item)
        let center = NotificationCenter.default
        watch = Publishers.Merge3(
            item.publisher(for: \.status).filter { $0 == .failed }.map { _ in false },
            center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).map { _ in false },
            center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item).map { _ in true })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ended in ended ? self?.trackEnded() : self?.fail() }
        player.volume = Float(volume * volume)
        player.play()
        self.player = player
        isPlaying = true
    }

    /// Repeat (or no other Active track): from the top. Play next: the next Active track.
    private func trackEnded() {
        let next = library.next(after: track.id)
        if next == track.id {
            player?.seek(to: .zero)
            player?.play()
        } else if let track = library.tracks.first(where: { $0.id == next }) {
            play(track)
        }
    }

    private func fail() {
        stop()
        failed = true
    }

    private func stop() {
        watch = nil
        player?.pause()
        player = nil
        isPlaying = false
    }

    // MARK: Files

    static func file(_ track: Track) -> URL { folder.appendingPathComponent(track.file) }

    func isDownloaded(_ track: Track) -> Bool { FileManager.default.fileExists(atPath: Self.file(track).path) }

    /// The track's file. Lofi Jazz streams from the Internet Archive until it's downloaded.
    private func source(_ track: Track) -> URL {
        track.isBuiltIn && !isDownloaded(track) ? Self.lofiJazzURL : Self.file(track)
    }

    /// Copies audio files picked in Finder into the Music folder, so moving the originals doesn't break them.
    /// They land in Library, not Active.
    func addFiles() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = true
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        for url in panel.urls {
            let id = UUID().uuidString
            let track = Track(id: id, name: url.deletingPathExtension().lastPathComponent, file: "\(id).\(url.pathExtension.lowercased())")
            guard (try? FileManager.default.copyItem(at: url, to: Self.file(track))) != nil else { continue }
            library.tracks.append(track)
        }
    }

    /// Drops an added track and moves its file to the Trash. Lofi Jazz can't be removed.
    func remove(_ track: Track) {
        guard !track.isBuiltIn else { return }
        if track == self.track {
            stop()
            self.track = .lofiJazz
        }
        library.remove(track.id)
        try? FileManager.default.trashItem(at: Self.file(track), resultingItemURL: nil)
    }

    /// Downloads Lofi Jazz into the Music folder, so it plays offline.
    func downloadLofiJazz() {
        downloadFailed = false
        downloadProgress = 0
        let target = Self.file(.lofiJazz)
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        var task: URLSessionDownloadTask!
        task = URLSession.shared.downloadTask(with: Self.lofiJazzURL) { temp, response, _ in
            // The temp file is gone once this returns, so it moves here, off the main thread.
            var saved = false
            if let temp, (response as? HTTPURLResponse)?.statusCode == 200 {
                saved = (try? FileManager.default.moveItem(at: temp, to: target)) != nil
            }
            DispatchQueue.main.async { Music.shared.downloadEnded(task, saved: saved) }
        }
        downloadWatch = task.progress.observe(\.fractionCompleted) { progress, _ in
            let fraction = progress.fractionCompleted
            DispatchQueue.main.async { Music.shared.downloadMoved(task, to: fraction) }
        }
        download = task
        task.resume()
    }

    func cancelDownload() {
        download?.cancel()
        download = nil
        downloadWatch = nil
        downloadProgress = nil
    }

    /// Progress comes per chunk; publishing whole percents keeps the views calm.
    private func downloadMoved(_ task: URLSessionDownloadTask, to fraction: Double) {
        guard task == download, let shown = downloadProgress, fraction - shown >= 0.01 else { return }
        downloadProgress = fraction
    }

    private func downloadEnded(_ task: URLSessionDownloadTask, saved: Bool) {
        guard task == download else { return }
        download = nil
        downloadWatch = nil
        downloadProgress = nil
        downloadFailed = !saved
    }
}

/// Music in the popover: a dropdown of tracks (Active, then Library), a round play button and a volume slider.
/// Picking a track plays it. Base size fits the popover, `scale` multiplies fonts and controls.
struct MusicControl: View {
    @ObservedObject var music: Music
    var scale: CGFloat = 1

    var body: some View {
        VStack(alignment: .leading, spacing: 10 * scale) {
            Menu {
                section("Active", music.library.activeTracks)
                section("Library", music.library.otherTracks)
            } label: {
                HStack {
                    Text(music.track.name)
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
                PlayButton(music: music, size: 36 * scale)
                Image(systemName: "speaker.wave.3.fill", variableValue: music.volume)
                    .foregroundStyle(.secondary)
                    .frame(width: 24 * scale)
                Slider(value: $music.volume, in: 0...1)
                    .tint(.green)
                    .controlSize(scale > 1.2 ? .extraLarge : .large)
            }

            if music.failed {
                Text("Can't play this track").font(.system(size: 13 * scale)).foregroundStyle(.red)
            }
        }
        .font(.system(size: 15 * scale))
    }

    @ViewBuilder private func section(_ title: String, _ tracks: [Track]) -> some View {
        if !tracks.isEmpty {
            Section(title) {
                ForEach(tracks) { track in
                    Toggle(track.name, isOn: Binding(get: { music.track == track }, set: { _ in music.play(track) }))
                }
            }
        }
    }
}

/// Green round play / pause button for the current track.
private struct PlayButton: View {
    @ObservedObject var music: Music
    let size: CGFloat

    var body: some View {
        Button(action: music.toggle) {
            Image(systemName: music.isPlaying ? "pause.fill" : "play.fill")
                .font(.system(size: size * 0.4))
                .foregroundStyle(.white)
                .frame(width: size, height: size)
                .background(Color.green, in: Circle())
        }
        .buttonStyle(.plain)
        .help(music.isPlaying ? "Pause" : "Play")
    }
}

/// Music tab in Settings: now playing with the volume, what a track's end does, then Active and Library.
/// Tracks move between the two with + and − or by dragging; dropping on an Active track puts it before that one.
struct MusicPane: View {
    @ObservedObject var music = Music.shared
    @Environment(\.uiScale) private var scale
    /// The track being renamed in place.
    @State private var renaming: String?

    var body: some View {
        Pane {
            Card { CardRow(divider: false) { nowPlaying } }
            Card {
                CardRow(divider: false) {
                    SettingRow(title: "When a track ends",
                               note: music.library.repeatTrack ? "It plays again. Active isn't used."
                                   : "The next Active track plays, after the last one it starts over.") {
                        HStack(spacing: 6 * scale) {
                            chip("Play next", repeatTrack: false)
                            chip("Repeat", repeatTrack: true)
                        }
                    }
                }
            }
            .padding(.top, 8 * scale)

            SectionTitle(title: "Active") {
                if music.library.repeatTrack { Text("Not used with Repeat").noteFont().foregroundStyle(.secondary) }
            }
            .padding(.top, 8 * scale)
            let active = music.library.activeTracks
            Card {
                if active.isEmpty { CardRow(divider: false) { Text("Drag tracks here or use +").foregroundStyle(.secondary) } }
                ForEach(Array(active.enumerated()), id: \.element.id) { index, track in
                    CardRow(divider: index > 0) { row(track, active: true) }
                        .dropDestination(for: String.self) { ids, _ in
                            ids.forEach { music.library.activate($0, at: index) }
                            return true
                        }
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                ids.forEach { music.library.activate($0) }
                return true
            }

            SectionTitle(title: "Library") {}.padding(.top, 8 * scale)
            let other = music.library.otherTracks
            Card {
                if other.isEmpty { CardRow(divider: false) { Text("Every track is Active").foregroundStyle(.secondary) } }
                ForEach(other) { track in
                    CardRow(divider: track.id != other.first?.id) { row(track, active: false) }
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                ids.forEach { music.library.deactivate($0) }
                return true
            }
            HStack {
                Spacer()
                Button { music.addFiles() } label: { Text("Add music…").bezelPadding() }
            }
        }
        .navigationTitle("Music")
    }

    /// Big play button, the track's name, the volume.
    private var nowPlaying: some View {
        HStack(spacing: 16 * scale) {
            PlayButton(music: music, size: 52 * scale)
            RowTitle(title: music.track.name) {
                if music.failed {
                    Text("Can't play this track").foregroundStyle(.red)
                } else {
                    Text(music.isPlaying ? "Playing" : "Paused")
                }
            }
            Spacer(minLength: 24 * scale)
            Image(systemName: "speaker.wave.3.fill", variableValue: music.volume)
                .foregroundStyle(.secondary)
            Slider(value: $music.volume, in: 0...1)
                .tint(.green)
                .frame(width: 240 * scale)
        }
    }

    private func chip(_ title: String, repeatTrack: Bool) -> some View {
        Toggle(isOn: Binding(get: { music.library.repeatTrack == repeatTrack },
                             set: { if $0 { music.library.repeatTrack = repeatTrack } })) {
            Text(title).bezelPadding()
        }
        .toggleStyle(.button)
    }

    /// Play button, name (with the download state for Lofi Jazz), then download, rename, remove and the
    /// Active switch. Drags by its ID.
    private func row(_ track: Track, active: Bool) -> some View {
        let current = track == music.track
        return HStack(spacing: 14 * scale) {
            Button { current ? music.toggle() : music.play(track) } label: {
                Image(systemName: current && music.isPlaying ? "pause.fill" : "play.fill")
                    .scaledFont(16)
                    .foregroundStyle(current ? Color.green : .secondary)
                    .frame(width: 28 * scale, height: 28 * scale)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help(current && music.isPlaying ? "Pause" : "Play")
            if renaming == track.id {
                NameField(name: track.name) { typed in
                    if let typed { music.library.rename(track.id, to: typed) }
                    renaming = nil
                }
            } else {
                VStack(alignment: .leading, spacing: 3 * scale) {
                    Text(track.name).fontWeight(current ? .semibold : .regular)
                    if track.isBuiltIn { downloadNote }
                }
            }
            Spacer()
            IconButton(symbol: "pencil", help: "Rename") { renaming = track.id }
            // Download sits in the trash column, Lofi Jazz can't be removed.
            if track.isBuiltIn {
                downloadButton
            } else {
                IconButton(symbol: "trash", help: "Remove, the file goes to the Trash") { music.remove(track) }
            }
            if active {
                IconButton(symbol: "minus.circle", help: "Remove from Active") { music.library.deactivate(track.id) }
            } else {
                IconButton(symbol: "plus.circle", help: "Add to Active") { music.library.activate(track.id) }
            }
        }
        .padding(.vertical, -4 * scale)
        .contentShape(Rectangle())
        .draggable(track.id)
    }

    @ViewBuilder private var downloadNote: some View {
        Group {
            if let progress = music.downloadProgress {
                Text("Downloading, \(Int(progress * 100))%")
            } else if music.downloadFailed {
                Text("Download failed").foregroundStyle(.red)
            } else if music.isDownloaded(.lofiJazz) {
                Text("8 h mix")
            } else {
                Text("8 h mix, streams until downloaded")
            }
        }
        .noteFont().foregroundStyle(.secondary)
    }

    @ViewBuilder private var downloadButton: some View {
        if let progress = music.downloadProgress {
            ProgressView(value: progress).frame(width: 100 * scale)
            IconButton(symbol: "xmark.circle", help: "Stop downloading") { music.cancelDownload() }
        } else if !music.isDownloaded(.lofiJazz) {
            IconButton(symbol: "arrow.down.circle", help: "Download to play offline, 471 MB") { music.downloadLofiJazz() }
        } else {
            Color.clear.frame(width: 30 * scale, height: 30 * scale)
        }
    }
}
