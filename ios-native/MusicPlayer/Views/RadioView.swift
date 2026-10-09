import SwiftUI

/// 电台 Tab（Radio Browser 免费 API，3 万+ 电台，无需 key）。
struct RadioStationItem: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let url: String
    let favicon: URL?
    let tags: [String]
    let country: String?
    let bitrate: Int
}

struct RadioView: View {
    @EnvironmentObject private var player: AudioPlayerManager

    @State private var stations: [RadioStationItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var selectedTag = ""

    private let tags = ["热门", "pop", "jazz", "classical", "rock", "electronic", "news", "chinese"]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // 标签横滑
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(tags, id: \.self) { tag in
                            RadioTagButton(
                                tag: tag,
                                isSelected: selectedTag == (tag == "热门" ? "" : tag),
                                onTap: {
                                    selectedTag = tag == "热门" ? "" : tag
                                    load()
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 16)
                }

                if isLoading && stations.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.top, 40)
                } else if let errorMessage {
                    RadioErrorView(message: errorMessage, onRetry: load)
                } else {
                    LazyVStack(spacing: 0) {
                        ForEach(stations) { station in
                            RadioStationRow(
                                station: station,
                                isPlaying: player.currentTrack?.title == station.name && player.isPlaying,
                                onPlay: { play(station) }
                            )
                        }
                    }
                }
            }
            .padding(.vertical, 12)
        }
        .navigationTitle("电台")
        .task { load() }
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                stations = try await MusicService.shared.radioStations(
                    tag: selectedTag.isEmpty ? nil : selectedTag
                )
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func play(_ station: RadioStationItem) {
        guard let url = URL(string: station.url) else { return }
        let track = Track(
            title: station.name,
            artist: station.country ?? "网络电台",
            album: "Radio",
            fileURL: url
        )
        player.playURLDirect(url, track: track)
    }
}

// MARK: - 标签按钮（拆分出来避免 body 类型检查超时）
private struct RadioTagButton: View {
    let tag: String
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(tag)
                .font(.subheadline)
                .fontWeight(isSelected ? .semibold : .regular)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(
                    Capsule()
                        .fill(isSelected
                              ? Color.blue.opacity(0.2)
                              : AppleTheme.secondaryLabel.opacity(0.12))
                )
                .foregroundColor(isSelected ? Color.blue : AppleTheme.label)
        }
        .pressable()
    }
}

// MARK: - 电台错误视图
private struct RadioErrorView: View {
    let message: String
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "antenna.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundColor(AppleTheme.secondaryLabel)
            Text(message)
                .foregroundColor(AppleTheme.secondaryLabel)
            Button("重试", action: onRetry).buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }
}

// MARK: - 电台行
private struct RadioStationRow: View {
    let station: RadioStationItem
    let isPlaying: Bool
    let onPlay: () -> Void

    var body: some View {
        Button(action: onPlay) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.blue.opacity(0.15))
                        .frame(width: 48, height: 48)
                    Image(systemName: "radio")
                        .foregroundColor(Color.blue)
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(station.name)
                        .font(.body)
                        .foregroundColor(AppleTheme.label)
                        .lineLimit(1)
                    RadioMetaRow(station: station)
                }
                Spacer()
                if isPlaying {
                    EqualizerBars()
                } else {
                    Image(systemName: "play.circle")
                        .font(.title2)
                        .foregroundColor(AppleTheme.secondaryLabel)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .pressable()
        Divider().padding(.leading, 76)
    }
}

// MARK: - 电台元信息行
private struct RadioMetaRow: View {
    let station: RadioStationItem

    var body: some View {
        HStack(spacing: 6) {
            if let country = station.country {
                Text(country)
            }
            if station.bitrate > 0 {
                Text("\(station.bitrate)kbps")
            }
        }
        .font(.caption)
        .foregroundColor(AppleTheme.secondaryLabel)
    }
}
