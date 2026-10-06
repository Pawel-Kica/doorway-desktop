import AVFoundation
import Combine
import MediaPlayer
import DoorwayDesktopCore
import SwiftUI

/// Plays music: the built-in Lofi Jazz mix and audio files added in Settings. One shared instance.
/// Saved in UserDefaults: `music` (JSON MusicLibrary), `musicTrack`, `musicVolume`,
/// `musicPositions` (each track's spot in seconds, so a track picks up where it was, across relaunches too).
/// It's the Mac's now playing app, so the play/pause key drives it instead of opening Apple Music.
@MainActor final class Music: ObservableObject {
    static let shared = Music()

    /// Where the tracks live: ~/Library/Application Support/DoorwayDesktop/Music.
    static let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("DoorwayDesktop/Music", isDirectory: true)
    /// Lorenzo Gambino's "Lofi Jazz" on the Internet Archive: one 8 h mix, 471 MB, CC0.
    static let lofiJazzURL = URL(string: "https://archive.org/download/lofi-jazz/Lofi%20Jazz.mp3")!

    @Published var library: MusicLibrary {
        didSet { UserDefaults.standard.set(try? JSONEncoder().encode(library), forKey: "music") }
    }
    @Published private(set) var track: Track {
        didSet { updateNowPlaying() }
    }
    @Published private(set) var isPlaying = false {
        didSet { updateNowPlaying() }
    }
    /// The track couldn't play (file gone, no network for the mix). The next play clears it.
    @Published private(set) var failed = false
    /// The slider, 0...1. Gain is its square, which feels more even than linear.
    @Published var volume: Double {
        didSet {
            UserDefaults.standard.set(volume, forKey: "musicVolume")
            player?.volume = Float(volume * volume)
        }
    }
    /// Where the current track is, in seconds.
    @Published private(set) var position: Double = 0
    /// Lofi Jazz download progress, 0...1, while it runs.
    @Published private(set) var downloadProgress: Double?
    @Published private(set) var downloadFailed = false

    private var player: AVPlayer?
    private var watch: AnyCancellable?
    private var ready: AnyCancellable?
    /// Records the spot once a second. Only added after the resume seek, so the start doesn't overwrite a saved spot.
    private var clock: Any?
    private var positions: [String: Double] {
        didSet { UserDefaults.standard.set(positions, forKey: "musicPositions") }
    }
    private var download: URLSessionDownloadTask?
    private var downloadWatch: NSKeyValueObservation?

    private init() {
        let defaults = UserDefaults.standard
        let library = defaults.data(forKey: "music").flatMap { try? JSONDecoder().decode(MusicLibrary.self, from: $0) }
            ?? .standard
        self.library = library
        track = library.tracks.first { $0.id == defaults.string(forKey: "musicTrack") } ?? .lofiJazz
        volume = defaults.object(forKey: "musicVolume") as? Double ?? 0.5
        positions = defaults.dictionary(forKey: "musicPositions") as? [String: Double] ?? [:]
        position = positions[track.id] ?? 0
        handleMediaKeys()
    }

    // MARK: Media keys

    /// Takes the play/pause key (and Control Center's buttons). macOS sends them to the now playing app, and with none
    /// it opens Apple Music, so this claims now playing from launch, paused. An app that starts playing later takes over.
    private func handleMediaKeys() {
        let commands = MPRemoteCommandCenter.shared()
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.toggle() }
            return .success
        }
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false { self?.toggle() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == true { self?.toggle() } }
            return .success
        }
        updateNowPlaying()
    }

    private func updateNowPlaying() {
        let center = MPNowPlayingInfoCenter.default()
        center.nowPlayingInfo = [MPMediaItemPropertyTitle: track.name, MPMediaItemPropertyArtist: "Doorway Desktop"]
        center.playbackState = isPlaying ? .playing : .paused
    }

    // MARK: Playback

    /// Plays a track from its saved spot, replacing whatever plays. The current one just keeps playing.
    func play(_ track: Track) {
        if track == self.track, player != nil {
            if !isPlaying { toggle() }
            return
        }
        stop()
        self.track = track
        UserDefaults.standard.set(track.id, forKey: "musicTrack")
        start()
    }

    /// Pause keeps the spot, play goes on from it.
    func toggle() {
        if isPlaying {
            player?.pause()
            savePosition()
            isPlaying = false
        } else if let player {
            player.play()
            isPlaying = true
        } else {
            start()
        }
    }

    /// The current track from 0:00.
    func startOver() {
        positions[track.id] = nil
        position = 0
        if let player, clock != nil {
            player.seek(to: .zero)
            player.play()
            isPlaying = true
        } else {
            start()
        }
    }

    /// Jumps forward (+) or back (−) by `seconds`. Paused with no player yet (after a relaunch), it moves the saved spot.
    func skip(_ seconds: Double) {
        let from = player == nil ? position : player?.currentTime().seconds ?? 0
        guard player == nil || clock != nil, from.isFinite else { return }
        let target = max(0, from + seconds)
        player?.seek(to: CMTime(seconds: target, preferredTimescale: 600))
        position = target
        positions[track.id] = target
    }

    /// Plays the current track from its saved spot. The seek waits for the item to be ready, playback waits for the seek.
    private func start() {
        stop()
        failed = false
        let resume = positions[track.id] ?? 0
        position = resume
        let item = AVPlayerItem(url: source(track))
        let player = AVPlayer(playerItem: item)
        let center = NotificationCenter.default
        watch = Publishers.Merge3(
            item.publisher(for: \.status).filter { $0 == .failed }.map { _ in false },
            center.publisher(for: AVPlayerItem.failedToPlayToEndTimeNotification, object: item).map { _ in false },
            center.publisher(for: AVPlayerItem.didPlayToEndTimeNotification, object: item).map { _ in true })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] ended in ended ? self?.trackEnded() : self?.fail() }
        ready = item.publisher(for: \.status).first { $0 == .readyToPlay }
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                player.seek(to: CMTime(seconds: resume, preferredTimescale: 600)) { _ in
                    DispatchQueue.main.async { self?.resumed(player) }
                }
            }
        player.volume = Float(volume * volume)
        self.player = player
        isPlaying = true
    }

    private func resumed(_ player: AVPlayer) {
        guard player == self.player else { return }
        clock = player.addPeriodicTimeObserver(forInterval: CMTime(seconds: 1, preferredTimescale: 600), queue: .main) {
            [weak self] _ in MainActor.assumeIsolated { self?.savePosition() }
        }
        if isPlaying { player.play() }
    }

    private func savePosition() {
        guard let player, clock != nil else { return }
        let seconds = player.currentTime().seconds
        guard seconds.isFinite else { return }
        position = seconds
        positions[track.id] = seconds
    }

    /// Repeat (or no other Active track): from the top. Play next: the next Active track.
    private func trackEnded() {
        let next = library.next(after: track.id)
        if next == track.id {
            positions[track.id] = nil
            player?.seek(to: .zero)
            player?.play()
        } else if let nextTrack = library.tracks.first(where: { $0.id == next }) {
            stop()
            positions[track.id] = nil
            play(nextTrack)
        }
    }

    private func fail() {
        stop()
        failed = true
    }

    private func stop() {
        savePosition()
        watch = nil
        ready = nil
        if let clock { player?.removeTimeObserver(clock) }
        clock = nil
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
            position = positions[Track.lofiJazz.id] ?? 0
        }
        positions[track.id] = nil
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

/// −30 s and +30 s buttons for the current track, glyphs `size` points.
private struct SkipButtons: View {
    @ObservedObject var music: Music
    let size: CGFloat

    var body: some View {
        HStack(spacing: size * 0.6) {
            button("gobackward.30", "Back 30 seconds", -30)
            button("goforward.30", "Forward 30 seconds", 30)
        }
    }

    private func button(_ symbol: String, _ help: String, _ seconds: Double) -> some View {
        Button { music.skip(seconds) } label: {
            Image(systemName: symbol).font(.system(size: size)).contentShape(Rectangle())
        }
        .buttonStyle(.borderless)
        .foregroundStyle(.secondary)
        .help(help)
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

/// Music tab in Settings: now playing (play, ±30 s, position, volume, Start over), what a track's end does, then Active and Library.
/// Tracks move between the two with + and −, or with the arrows past the edge (going to Library asks first).
struct MusicPane: View {
    @ObservedObject var music = Music.shared
    @Environment(\.uiScale) private var scale
    /// The track being renamed in place.
    @State private var renaming: String?
    /// The last Active track whose down arrow was clicked, waiting on the confirm to go to Library.
    @State private var leaving: Track?

    var body: some View {
        Pane {
            SectionTitle(title: "Music") {}
            Card { CardRow(divider: false) { nowPlaying } }
            Card {
                CardRow(divider: false) {
                    SettingRow(title: "When a track ends") {
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
                if active.isEmpty { CardRow(divider: false) { Text("Add tracks with +").foregroundStyle(.secondary) } }
                ForEach(active) { track in
                    CardRow(divider: track.id != active.first?.id) {
                        row(track, active: true, first: track.id == active.first?.id, last: track.id == active.last?.id)
                    }
                }
            }

            SectionTitle(title: "Library") {}.padding(.top, 8 * scale)
            let other = music.library.otherTracks
            Card {
                if other.isEmpty { CardRow(divider: false) { Text("Every track is Active").foregroundStyle(.secondary) } }
                ForEach(other) { track in
                    CardRow(divider: track.id != other.first?.id) {
                        row(track, active: false, first: track.id == other.first?.id, last: track.id == other.last?.id)
                    }
                }
            }
            HStack {
                Spacer()
                Button { music.addFiles() } label: { Text("Add music…").bezelPadding() }
            }
        }
        .navigationTitle("Music")
        .alert("Move \(leaving?.name ?? "") to Library?", isPresented: Binding(get: { leaving != nil }, set: { if !$0 { leaving = nil } })) {
            Button("Move") { if let leaving { music.library.move(leaving.id, by: 1) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(music.library.active.count == 1
                 ? "Active will be empty, so a track that ends plays again."
                 : "Play next only goes through Active tracks.")
        }
    }

    /// Big play button, the track's name, volume and Start over.
    private var nowPlaying: some View {
        HStack(spacing: 16 * scale) {
            PlayButton(music: music, size: 52 * scale)
            SkipButtons(music: music, size: 22 * scale)
            RowTitle(title: music.track.name) {
                if music.failed {
                    Text("Can't play this track").foregroundStyle(.red)
                } else {
                    Text("\(music.isPlaying ? "Playing" : "Paused") · \(Duration.seconds(music.position).formatted(.time(pattern: .hourMinuteSecond)))")
                }
            }
            Spacer()
            Image(systemName: "speaker.wave.3.fill", variableValue: music.volume)
                .foregroundStyle(.secondary)
            Slider(value: $music.volume, in: 0...1)
                .tint(.green)
                .frame(width: 140 * scale)
            Button { music.startOver() } label: { Text("Start over").bezelPadding() }
                .disabled(music.position < 1)
        }
    }

    private func chip(_ title: String, repeatTrack: Bool) -> some View {
        Toggle(isOn: Binding(get: { music.library.repeatTrack == repeatTrack },
                             set: { if $0 { music.library.repeatTrack = repeatTrack } })) {
            Text(title).bezelPadding()
        }
        .toggleStyle(.button)
    }

    /// Play button, name (with the download state for Lofi Jazz), then up and down, rename, the Active switch and
    /// remove last (download for Lofi Jazz). The arrows run over Active then Library, see `MusicLibrary.move`.
    private func row(_ track: Track, active: Bool, first: Bool = false, last: Bool = false) -> some View {
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
            IconButton(symbol: "arrow.up", help: active || !first ? "Move up" : "Move up to Active") {
                music.library.move(track.id, by: -1)
            }
            .disabled(active && first)
            IconButton(symbol: "arrow.down", help: !active || !last ? "Move down" : "Move down to Library") {
                if active && last { leaving = track } else { music.library.move(track.id, by: 1) }
            }
            .disabled(!active && last)
            IconButton(symbol: "pencil", help: "Rename") { renaming = track.id }
            if active {
                IconButton(symbol: "minus.circle", help: "Remove from Active") { music.library.deactivate(track.id) }
            } else {
                IconButton(symbol: "plus.circle", help: "Add to Active") { music.library.activate(track.id) }
            }
            // Download sits in the trash column, Lofi Jazz can't be removed.
            if track.isBuiltIn {
                downloadButton
            } else {
                IconButton(symbol: "trash", help: "Remove, the file goes to the Trash") { music.remove(track) }
            }
        }
        .padding(.vertical, -4 * scale)
    }

    @ViewBuilder private var downloadNote: some View {
        Group {
            if let progress = music.downloadProgress {
                Text("Downloading, \(Int(progress * 100))%")
            } else if music.downloadFailed {
                Text("Download failed").foregroundStyle(.red)
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
