import SwiftUI

/// 波形进度条（namida waveform.dart 的 iOS 版）。
/// namida 是端侧解码（耗电），我们是服务端 ffmpeg 预计算 peaks 存 DB，
/// App 只负责 Canvas 渲染——一次画完所有 bar，零耗电秒渲染。
/// 超越点：namida 每次打开都要解码，我们一次计算永久复用。
struct WaveformProgressView: View {
    /// 后端曲目 UUID（在线歌曲）；本地文件传 nil 则用默认样式
    var trackId: String?
    var accentColor: Color = AppleTheme.accent

    @EnvironmentObject private var player: AudioPlayerManager
    @State private var peaks: [Float] = []
    @State private var isSeeking = false
    @State private var seekValue: Double = 0

    private let barCount = 64

    var body: some View {
        VStack(spacing: 6) {
            GeometryReader { geo in
                Canvas { context, size in
                    let bars = displayBars
                    let barWidth = size.width / CGFloat(bars.count)
                    let progress = isSeeking
                        ? seekValue / max(player.duration, 1)
                        : player.currentTime / max(player.duration, 1)
                    for (i, peak) in bars.enumerated() {
                        let h = max(2, CGFloat(peak) * size.height)
                        let x = CGFloat(i) * barWidth + barWidth / 2
                        let played = CGFloat(i) / CGFloat(bars.count) <= progress
                        let rect = CGRect(
                            x: x - barWidth * 0.32,
                            y: (size.height - h) / 2,
                            width: barWidth * 0.64,
                            height: h
                        )
                        let path = RoundedRectangle(cornerRadius: barWidth * 0.32).path(in: rect)
                        context.fill(
                            path,
                            with: .color(played
                                ? accentColor
                                : AppleTheme.secondaryLabel.opacity(0.35))
                        )
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            isSeeking = true
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            seekValue = ratio * player.duration
                        }
                        .onEnded { value in
                            let ratio = min(max(value.location.x / geo.size.width, 0), 1)
                            player.seek(to: ratio * player.duration)
                            isSeeking = false
                        }
                )
            }
            .frame(height: 44)

            HStack {
                Text(formatDuration(isSeeking ? seekValue : player.currentTime))
                Spacer()
                Text(formatDuration(player.duration))
            }
            .font(.caption)
            .foregroundColor(AppleTheme.secondaryLabel)
            .monospacedDigit()
        }
        .task(id: trackId) { await loadPeaks() }
    }

    /// 显示用 bar：有 peaks 则降采样到 64，无则用正弦占位
    private var displayBars: [Float] {
        if peaks.isEmpty {
            return (0..<barCount).map { i in
                let t = Float(i) / Float(barCount)
                return 0.25 + 0.35 * abs(sin(t * 12.0)) + 0.15 * abs(sin(t * 31.0))
            }
        }
        let step = Float(peaks.count) / Float(barCount)
        return (0..<barCount).map { i in
            let idx = min(Int(Float(i) * step), peaks.count - 1)
            return peaks[idx]
        }
    }

    private func loadPeaks() async {
        guard let trackId = trackId, !trackId.isEmpty else { return }
        do {
            peaks = try await MusicService.shared.waveform(id: trackId)
        } catch {
            peaks = []
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }
        let m = Int(seconds) / 60
        let s = Int(seconds) % 60
        return String(format: "%d:%02d", m, s)
    }
}
