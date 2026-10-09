import Foundation
import AVFoundation
import Combine
import MediaPlayer

// Views 适配（2026-10-09）：playOnline 改为直调 MusicService.streamURL（每次现取，
// 预签名 URL 会过期，禁止缓存），播放开始后上报 reportPlay；删掉无用的通知转发。
/// 音频播放器 - 干净重写版
class AudioPlayerManager: ObservableObject {
    @Published private(set) var currentTrack: Track?
    @Published private(set) var isPlaying: Bool = false
    @Published var currentTime: Double = 0
    @Published var duration: Double = 0
    
    private var player: AVPlayer?
    private var timeObserver: Any?
    private var queue: [Track] = []
    private var currentIndex: Int = 0
    
    init() {
        setupAudioSession()
        setupRemoteCommands()
    }
    
    func play(_ track: Track) {
        currentTrack = track
        queue = [track]
        currentIndex = 0
        playCurrent()
    }
    
    func playTracks(_ tracks: [Track], startAt index: Int = 0) {
        guard !tracks.isEmpty else { return }
        queue = tracks
        currentIndex = min(index, tracks.count - 1)
        currentTrack = queue[currentIndex]
        playCurrent()
    }
    
    func playOnlineSongs(_ songs: [OnlineSong], startAt index: Int = 0) {
        let tracks = songs.map { song in
            Track(
                title: song.title,
                artist: song.artist,
                album: song.album,
                onlineSongId: song.id
            )
        }
        playTracks(tracks, startAt: index)
    }

    /// 播放平台歌曲（网易云/QQ/酷狗）：直链经后端 302，AVPlayer 原生跟随
    @MainActor
    func playPlatformTracks(_ songs: [PlatformTrack], startAt index: Int = 0) {
        let tracks: [Track] = songs.compactMap { song in
            guard let url = try? MusicService.shared.platformStreamURL(
                platform: song.platform,
                platformId: song.platformId
            ) else { return nil }
            return Track(
                title: song.title,
                artist: song.artist,
                album: song.album,
                duration: song.duration,
                artworkURL: song.coverURL,
                platformStreamURL: url,
                platform: song.platform
            )
        }
        guard !tracks.isEmpty else { return }
        playTracks(tracks, startAt: min(index, tracks.count - 1))
    }
    
    func togglePlayPause() {
        guard let player = player else { return }
        if isPlaying {
            player.pause()
        } else {
            player.play()
        }
        isPlaying.toggle()
        updateNowPlaying()
    }
    
    func next() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex + 1) % queue.count
        currentTrack = queue[currentIndex]
        playCurrent()
    }
    
    func previous() {
        guard !queue.isEmpty else { return }
        currentIndex = (currentIndex - 1 + queue.count) % queue.count
        currentTrack = queue[currentIndex]
        playCurrent()
    }
    
    func seek(to seconds: Double) {
        let time = CMTime(seconds: seconds, preferredTimescale: 600)
        player?.seek(to: time)
        currentTime = seconds
    }
    
    private func playCurrent() {
        guard let track = currentTrack else { return }

        // 平台直链优先：后端 302 到真实地址，AVPlayer 直接播
        if let platformURL = track.platformStreamURL {
            playURL(platformURL, track: track)
        } else if let songId = track.onlineSongId {
            // 如果有在线ID，通过API获取播放地址
            Task {
                await playOnline(songId: songId, track: track)
            }
        } else if let url = track.fileURL {
            playURL(url, track: track)
        }
    }
    
    private func playOnline(songId: String, track: Track) async {
        do {
            // 每次现取播放地址：COS 预签名 URL 有过期时间，禁止缓存
            let url = try await MusicService.shared.streamURL(id: songId)
            await MainActor.run { playURL(url, track: track) }
            // 播放开始后上报统计（需登录；失败不阻塞播放）
            if await AuthService.shared.isLoggedIn {
                try? await MusicService.shared.reportPlay(id: songId)
            }
        } catch {
            print("[AudioPlayerManager] 在线播放失败: \(error)")
        }
    }
    
    private func playURL(_ url: URL, track: Track) {
        let item = AVPlayerItem(url: url)
        // 真 FFT 频谱：把 MTAudioProcessingTap 挂到 item 的 audioMix
        SpectrumAnalyzer.shared.attach(to: item)
        if player == nil {
            player = AVPlayer(playerItem: item)
            addTimeObserver()
            SleepTimerManager.shared.bind(player: player)
        } else {
            player?.replaceCurrentItem(with: item)
        }
        player?.play()
        isPlaying = true
        duration = track.duration
        updateNowPlaying()
    }
    
    func playURLDirect(_ url: URL, track: Track, duration: Double = 0) {
        playURL(url, track: track)
        if duration > 0 {
            self.duration = duration
        }
    }
    
    private func setupAudioSession() {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("Audio session error: \(error)")
        }
    }
    
    private func addTimeObserver() {
        let interval = CMTime(seconds: 0.5, preferredTimescale: 600)
        timeObserver = player?.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            self?.currentTime = time.seconds
            if let duration = self?.player?.currentItem?.duration.seconds,
               duration.isFinite {
                self?.duration = duration
            }
        }
    }
    
    private func setupRemoteCommands() {
        let center = MPRemoteCommandCenter.shared()
        center.playCommand.addTarget { [weak self] _ in
            if self?.isPlaying == false { self?.togglePlayPause() }
            return .success
        }
        center.pauseCommand.addTarget { [weak self] _ in
            if self?.isPlaying == true { self?.togglePlayPause() }
            return .success
        }
        center.nextTrackCommand.addTarget { [weak self] _ in
            self?.next()
            return .success
        }
        center.previousTrackCommand.addTarget { [weak self] _ in
            self?.previous()
            return .success
        }
    }
    
    private func updateNowPlaying() {
        guard let track = currentTrack else { return }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title,
            MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album,
        ]
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
    }
}
