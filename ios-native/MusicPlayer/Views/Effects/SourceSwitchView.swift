import SwiftUI

/// 手动换源选择器（lx-music 手动换源的 iOS 版）。
/// 长按歌曲行打开：自动 / 本地 / 各平台最佳匹配，锁定后播放走该源，
/// 源失效时后端自动降级（不断播）。
struct SourceSwitchView: View {
    let song: OnlineSong
    @Environment(\.dismiss) private var dismiss

    @State private var sources: TrackSources?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var setting: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if let sources = sources {
                    List {
                        Section {
                            sourceRow(
                                id: "auto",
                                title: "自动",
                                subtitle: "本地优先，失败自动换平台",
                                icon: "wand.and.stars",
                                isCurrent: sources.preferredSource == "auto"
                            )
                            if !sources.local.isEmpty {
                                let qualities = sources.local
                                    .map { "\($0.quality)" }
                                    .joined(separator: " / ")
                                sourceRow(
                                    id: "local",
                                    title: "本地",
                                    subtitle: "码率：\(qualities)",
                                    icon: "internaldrive",
                                    isCurrent: sources.preferredSource == "local"
                                )
                            }
                        }
                        if !sources.platforms.isEmpty {
                            Section("平台源") {
                                ForEach(sources.platforms) { p in
                                    sourceRow(
                                        id: p.platform,
                                        title: p.displayName,
                                        subtitle: "\(p.title) - \(p.artist)",
                                        icon: "cloud",
                                        isCurrent: sources.preferredSource == p.platform
                                    )
                                }
                            }
                        }
                        Section {
                            Text("锁定平台源后，播放走该平台直链；源失效时自动降级本地，不会断播。")
                                .font(.footnote)
                                .foregroundColor(AppleTheme.secondaryLabel)
                        }
                    }
                } else {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.largeTitle)
                            .foregroundColor(AppleTheme.secondaryLabel)
                        Text(errorMessage ?? "加载失败")
                            .foregroundColor(AppleTheme.secondaryLabel)
                        Button("重试") { load() }
                            .buttonStyle(.bordered)
                    }
                }
            }
            .navigationTitle("换源 · \(song.title)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .task { load() }
    }

    private func sourceRow(id: String, title: String, subtitle: String, icon: String, isCurrent: Bool) -> some View {
        Button {
            setSource(id)
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .foregroundColor(Color.blue)
                    .frame(width: 24)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundColor(AppleTheme.label)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundColor(AppleTheme.secondaryLabel)
                        .lineLimit(1)
                }
                Spacer()
                if setting == id {
                    ProgressView()
                } else if isCurrent {
                    Image(systemName: "checkmark")
                        .foregroundColor(Color.blue)
                }
            }
        }
        .disabled(setting != nil)
    }

    private func load() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                let result = try await MusicService.shared.availableSources(id: song.id)
                sources = result
            } catch {
                errorMessage = error.localizedDescription
            }
            isLoading = false
        }
    }

    private func setSource(_ id: String) {
        setting = id
        Task {
            do {
                try await MusicService.shared.setPreferredSource(id: song.id, source: id)
                // 刷新选中态
                let result = try await MusicService.shared.availableSources(id: song.id)
                sources = result
            } catch {
                errorMessage = error.localizedDescription
            }
            setting = nil
        }
    }
}
