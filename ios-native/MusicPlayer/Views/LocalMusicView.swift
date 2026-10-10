import SwiftUI

// MARK: - LocalMusicView（2026-10-09 Apple 原生风重做）
//
// 职责：本地音乐页（LibraryStore 持久化的曲目）。
//   - 原生列表风：封面 + 标题/歌手·时长
//   - 点击播放/暂停；左滑删除

struct LocalMusicView: View {
    @EnvironmentObject private var library: LibraryStore
    @EnvironmentObject private var player: AudioPlayerManager
    @EnvironmentObject private var theme: ThemeSettings

    var body: some View {
        ZStack {
            AppleTheme.background.ignoresSafeArea()
            if library.tracks.isEmpty {
                EmptyStateView(
                    icon: "folder",
                    title: "本地还没有音乐",
                    subtitle: "在其他页面可加入本地库"
                )
            } else {
                List {
                    ForEach(Array(library.tracks.enumerated()), id: \.element.id) { idx, track in
                        localRow(track, index: idx)
                            .listRowInsets(EdgeInsets(top: 4, leading: 12, bottom: 4, trailing: 12))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                    .onDelete { offsets in
                        for i in offsets {
                            library.remove(library.tracks[i])
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
            }
        }
        .navigationTitle("本地 (\(library.tracks.count))")
        .onAppear { library.refresh() }
    }

    private func localRow(_ track: Track, index: Int) -> some View {
        let isCurrent = player.currentTrack?.id == track.id
        return Button {
            if isCurrent {
                player.togglePlayPause()
            } else {
                player.playTracks(library.tracks, startAt: index)
            }
        } label: {
            HStack(spacing: 12) {
                coverArt(url: track.artworkURL, size: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(track.title)
                        .font(.body)
                        .foregroundColor(AppleTheme.label)
                        .lineLimit(1)
                    Text("\(track.artist) · \(formatDuration(track.duration))")
                        .font(.body)
                        .foregroundColor(AppleTheme.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer()
                if isCurrent {
                    Image(systemName: "waveform")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(theme.accentColor)
                }
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .pressable()
    }
}
