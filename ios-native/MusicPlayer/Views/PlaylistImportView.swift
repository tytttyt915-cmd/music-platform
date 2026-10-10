import SwiftUI

// MARK: - PlaylistImportView（v4.2）
//
// 歌单导入（一键搬家）：粘贴网易云 / QQ 音乐歌单链接 → 后端爬取 → 本地匹配 → 建单。
// 后端：POST /playlists/import（Scrapling 爬虫 + 逐首本地匹配，竞品都没有的杀手功能）
//
// 流程：
//   idle → 输入链接 → importing（转圈，后端同步爬取，可能 10~60 秒）
//   → done（搬家报告：命中 X/Y，未命中列表可手动搜）
//   → error（链接非法 / 歌单为空 / 抓取失败）

struct PlaylistImportView: View {
    @EnvironmentObject private var music: MusicService
    @EnvironmentObject private var theme: ThemeSettings

    @State private var urlText = ""
    @State private var phase: Phase = .idle
    @State private var report: PlaylistImportReport?
    @State private var errorMessage: String?

    private enum Phase {
        case idle, importing, done, error
    }

    var body: some View {
        ZStack(alignment: .top) {
            AppleTheme.background.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 20) {
                    // 说明卡
                    introCard
                        .padding(.horizontal, 12)
                        .padding(.top, 8)

                    // 输入区
                    inputCard
                        .padding(.horizontal, 12)

                    // 状态区
                    switch phase {
                    case .idle:
                        supportedList
                            .padding(.horizontal, 12)
                    case .importing:
                        importingView
                            .padding(.horizontal, 12)
                    case .done:
                        if let report {
                            reportView(report)
                                .padding(.horizontal, 12)
                        }
                    case .error:
                        EmptyStateView(
                            icon: "exclamationmark.triangle",
                            title: "导入失败",
                            subtitle: errorMessage ?? "未知错误"
                        )
                        .padding(.horizontal, 12)
                    }

                    Spacer(minLength: 24)
                }
                .padding(.bottom, 24)
            }
        }
        .navigationTitle("歌单导入")
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - 说明卡

    private var introCard: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(theme.accentColor.opacity(0.15))
                    .frame(width: 44, height: 44)
                Image(systemName: "square.and.arrow.down.on.square")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(theme.accentColor)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("一键搬家")
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(AppleTheme.label)
                Text("把你在其他 App 的歌单搬过来，自动匹配本地曲库")
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
            }
            Spacer()
        }
        .padding(12)
        .liquidGlassLight(cornerRadius: 16)
    }

    // MARK: - 输入区

    private var inputCard: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "link")
                    .foregroundColor(AppleTheme.secondaryLabel)
                TextField("粘贴网易云 / QQ 音乐歌单链接", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .font(.body)
                    .foregroundColor(AppleTheme.label)
                if !urlText.isEmpty {
                    Button {
                        urlText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(AppleTheme.tertiaryLabel)
                    }
                }
            }
            .padding(12)
            .background(AppleTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 12))

            Button {
                startImport()
            } label: {
                HStack {
                    Spacer()
                    Text("开始搬家")
                        .font(.headline)
                        .fontWeight(.semibold)
                    Spacer()
                }
                .padding(.vertical, 14)
                .background(canImport ? theme.accentColor : AppleTheme.tertiaryLabel.opacity(0.3))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(!canImport)
            .pressable()
        }
        .padding(12)
        .liquidGlassLight(cornerRadius: 16)
    }

    private var canImport: Bool {
        phase == .idle || phase == .done || phase == .error
    }

    private var supportedList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("支持的链接")
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(AppleTheme.label)
            ForEach([
                ("music.163.com", "网易云音乐歌单页链接"),
                ("y.qq.com", "QQ 音乐歌单页链接"),
            ], id: \.0) { domain, desc in
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundColor(.green)
                    Text(domain)
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundColor(AppleTheme.label)
                    Text(desc)
                        .font(.caption)
                        .foregroundColor(AppleTheme.secondaryLabel)
                }
            }
            Text("未命中的歌曲会列在报告里，可手动搜索添加")
                .font(.caption)
                .foregroundColor(AppleTheme.tertiaryLabel)
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
    }

    // MARK: - 导入中

    private var importingView: some View {
        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.4)
                .tint(theme.accentColor)
            VStack(spacing: 6) {
                Text("正在搬家…")
                    .font(.headline)
                    .foregroundColor(AppleTheme.label)
                Text("抓取歌单 → 逐首匹配本地曲库\n歌曲多的话需要几十秒，别关掉")
                    .font(.caption)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
        .liquidGlassLight(cornerRadius: 16)
    }

    // MARK: - 搬家报告

    private func reportView(_ report: PlaylistImportReport) -> some View {
        VStack(spacing: 16) {
            // 结果头
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .fill(Color.green.opacity(0.15))
                        .frame(width: 64, height: 64)
                    Image(systemName: "checkmark")
                        .font(.system(size: 28, weight: .bold))
                        .foregroundColor(.green)
                }
                Text("搬家完成")
                    .font(.headline)
                    .foregroundColor(AppleTheme.label)
                Text("「\(report.playlistName)」")
                    .font(.subheadline)
                    .foregroundColor(AppleTheme.secondaryLabel)
                    .lineLimit(1)
                // 命中率
                HStack(spacing: 16) {
                    statColumn(value: "\(report.total)", label: "共抓取")
                    statColumn(value: "\(report.matched)", label: "已匹配", color: .green)
                    statColumn(value: "\(report.total - report.matched)", label: "未命中", color: .orange)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 20)
            .liquidGlassLight(cornerRadius: 16)

            // 未命中列表
            if !report.unmatched.isEmpty {
                VStack(alignment: .leading, spacing: 0) {
                    Text("未命中的歌曲（\(report.unmatched.count)）")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(AppleTheme.label)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 10)
                    ForEach(report.unmatched) { song in
                        HStack(spacing: 10) {
                            Image(systemName: "questionmark.circle")
                                .foregroundColor(.orange)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(song.title)
                                    .font(.body)
                                    .foregroundColor(AppleTheme.label)
                                    .lineLimit(1)
                                Text(song.artist)
                                    .font(.caption)
                                    .foregroundColor(AppleTheme.secondaryLabel)
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        Divider()
                            .padding(.leading, 44)
                    }
                }
                .liquidGlassLight(cornerRadius: 16)
            }

            // 再搬一个
            Button {
                urlText = ""
                phase = .idle
                self.report = nil
            } label: {
                Text("再搬一个歌单")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(theme.accentColor)
                    .padding(.vertical, 10)
            }
        }
    }

    private func statColumn(value: String, label: String, color: Color = AppleTheme.label) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(color)
            Text(label)
                .font(.caption)
                .foregroundColor(AppleTheme.secondaryLabel)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - 导入

    private func startImport() {
        let trimmed = urlText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        phase = .importing
        errorMessage = nil
        report = nil
        Task {
            do {
                let result = try await music.importPlaylist(url: trimmed)
                await MainActor.run {
                    self.report = result
                    phase = .done
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    phase = .error
                }
            }
        }
    }
}
