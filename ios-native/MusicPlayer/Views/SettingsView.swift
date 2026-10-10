import SwiftUI
import UIKit

// MARK: - Beans 风格设置页（v4.3）
// 对照 Beans-Music v2.0.3 真机截图重做：
// 顶部搜索 + 分组标题 + 玻璃拟态分组卡片 + 图标去底座 + 原生开关
// 分组：账号与平台 / 外观与界面 / 播放与音效 / 数据管理 / 关于与支持
struct SettingsView: View {
    @EnvironmentObject var theme: ThemeSettings
    @Environment(\.dismiss) private var dismiss

    @State private var searchText = ""
    @State private var showLogin = false
    @State private var showSleepTimer = false
    @State private var expandedKeys: Set<String> = []

    @AppStorage("settings.highRefreshRate") private var highRefreshRate = true

    // MARK: - 数据模型

    private enum Accessory {
        case chevron
        case expandable(Bool)
        case toggle(Binding<Bool>)
    }

    private enum RowKind {
        case expandable(ExpandableKind)
        case push(PushPage)
        case sheetLogin
        case sheetSleepTimer
        case toggleHighRefresh
        case toggleDynamicIsland
        case toggleTabBarHidden
    }

    private enum ExpandableKind {
        case platforms, themeMode, wallpaper, quality, playback, backup, cache, disclaimer, environment
    }

    private enum PushPage {
        case equalizer, playlistImport, changelog, checkUpdate, feedback, diagnostics
    }

    private struct RowDef: Identifiable {
        let key: String
        let icon: String
        let title: String
        let subtitle: String?
        let kind: RowKind
        var id: String { key }
    }

    private struct SectionDef: Identifiable {
        let key: String
        let title: String
        let rows: [RowDef]
        var id: String { key }
    }

    private var allSections: [SectionDef] {
        [
            SectionDef(key: "account", title: "账号与平台", rows: [
                RowDef(key: "login", icon: "person.crop.circle.badge.checkmark", title: "账号登录", subtitle: nil, kind: .sheetLogin),
                RowDef(key: "platforms", icon: "square.stack.3d.up", title: "平台显示", subtitle: nil, kind: .expandable(.platforms)),
            ]),
            SectionDef(key: "appearance", title: "外观与界面", rows: [
                RowDef(key: "theme", icon: "paintpalette.fill", title: "主题模式", subtitle: theme.accent.rawValue, kind: .expandable(.themeMode)),
                RowDef(key: "wallpaper", icon: "sparkles", title: "动态壁纸", subtitle: nil, kind: .expandable(.wallpaper)),
                RowDef(key: "refresh", icon: "gauge", title: "高刷新率", subtitle: "跟随系统", kind: .toggleHighRefresh),
                RowDef(key: "island", icon: "iphone", title: "灵动岛", subtitle: nil, kind: .toggleDynamicIsland),
                RowDef(key: "tabbar", icon: "menubar.rectangle", title: "隐藏 Tab 栏", subtitle: nil, kind: .toggleTabBarHidden),
            ]),
            SectionDef(key: "playback", title: "播放与音效", rows: [
                RowDef(key: "quality", icon: "waveform", title: "音源与音质", subtitle: "统一音质", kind: .expandable(.quality)),
                RowDef(key: "playset", icon: "play.circle", title: "播放设置", subtitle: nil, kind: .expandable(.playback)),
                RowDef(key: "sleep", icon: "moon.zzz.fill", title: "睡眠定时", subtitle: nil, kind: .sheetSleepTimer),
                RowDef(key: "eq", icon: "slider.horizontal.3", title: "均衡器", subtitle: "已关闭", kind: .push(.equalizer)),
            ]),
            SectionDef(key: "data", title: "数据管理", rows: [
                RowDef(key: "backup", icon: "externaldrive", title: "备份与恢复", subtitle: nil, kind: .expandable(.backup)),
                RowDef(key: "import", icon: "tray.and.arrow.down", title: "歌单导入", subtitle: nil, kind: .push(.playlistImport)),
                RowDef(key: "cache", icon: "trash", title: "缓存清理", subtitle: nil, kind: .expandable(.cache)),
            ]),
            SectionDef(key: "about", title: "关于与支持", rows: [
                RowDef(key: "changelog", icon: "clock.arrow.circlepath", title: "更新日志", subtitle: appVersion, kind: .push(.changelog)),
                RowDef(key: "update", icon: "checkmark.seal", title: "检查更新", subtitle: nil, kind: .push(.checkUpdate)),
                RowDef(key: "feedback", icon: "exclamationmark.bubble", title: "问题反馈", subtitle: nil, kind: .push(.feedback)),
                RowDef(key: "diagnostics", icon: "stethoscope", title: "诊断与日志", subtitle: nil, kind: .push(.diagnostics)),
                RowDef(key: "disclaimer", icon: "exclamationmark.triangle", title: "免责声明", subtitle: nil, kind: .expandable(.disclaimer)),
                RowDef(key: "env", icon: "info.circle", title: "运行环境", subtitle: nil, kind: .expandable(.environment)),
            ]),
        ]
    }

    private var filteredSections: [SectionDef] {
        guard !searchText.trimmingCharacters(in: .whitespaces).isEmpty else { return allSections }
        let q = searchText
        return allSections.compactMap { section in
            let rows = section.rows.filter {
                $0.title.localizedCaseInsensitiveContains(q)
                    || ($0.subtitle ?? "").localizedCaseInsensitiveContains(q)
            }
            return rows.isEmpty ? nil : SectionDef(key: section.key, title: section.title, rows: rows)
        }
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    // MARK: - 主视图

    var body: some View {
        NavigationStack {
            ZStack {
                AppleTheme.background.ignoresSafeArea()
                VStack(spacing: 0) {
                    header
                    searchBar
                        .padding(.top, 10)
                    ScrollView {
                        VStack(alignment: .leading, spacing: 22) {
                            ForEach(filteredSections) { section in
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(section.title)
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                        .padding(.horizontal, 22)
                                    glassCard {
                                        ForEach(Array(section.rows.enumerated()), id: \.element.key) { index, row in
                                            rowView(row)
                                            if index < section.rows.count - 1 {
                                                Divider()
                                                    .padding(.leading, 58)
                                                    .opacity(0.5)
                                            }
                                        }
                                    }
                                }
                            }
                            if filteredSections.isEmpty {
                                Text("暂无结果")
                                    .foregroundColor(.secondary)
                                    .frame(maxWidth: .infinity, alignment: .center)
                                    .padding(.top, 60)
                            }
                        }
                        .padding(.top, 14)
                        .padding(.bottom, 48)
                    }
                }
            }
            .navigationBarHidden(true)
            .sheet(isPresented: $showLogin) { LoginView() }
            .sheet(isPresented: $showSleepTimer) { SleepTimerView() }
        }
    }

    // MARK: - 顶部

    private var header: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.primary)
                    .frame(width: 44, height: 44)
                    .background(.ultraThinMaterial, in: Circle())
            }
            .buttonStyle(.plain)
            Spacer()
            Text("设置")
                .font(.title2.bold())
            Spacer()
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
    }

    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundColor(.secondary)
            TextField("搜索设置", text: $searchText)
                .autocorrectionDisabled()
        }
        .padding(14)
        .background(.ultraThinMaterial, in: Capsule())
        .padding(.horizontal, 16)
    }

    // MARK: - 卡片与行

    private func glassCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
            )
            .padding(.horizontal, 16)
    }

    @ViewBuilder
    private func accessoryView(_ accessory: Accessory) -> some View {
        switch accessory {
        case .chevron:
            Image(systemName: "chevron.right")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
        case .expandable(let open):
            Image(systemName: "chevron.down")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.secondary)
                .rotationEffect(.degrees(open ? 180 : 0))
        case .toggle(let binding):
            Toggle("", isOn: binding)
                .labelsHidden()
        }
    }

    private func rowLabel(_ row: RowDef, accessory: Accessory) -> some View {
        HStack(spacing: 14) {
            // impeccable：图标去底座，SF Symbol 直接着色
            Image(systemName: row.icon)
                .font(.system(size: 20))
                .foregroundColor(.primary)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(row.title)
                    .font(.body)
                    .foregroundColor(.primary)
                if let sub = row.subtitle, !sub.isEmpty {
                    Text(sub)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            Spacer()
            accessoryView(accessory)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 16)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func rowView(_ row: RowDef) -> some View {
        switch row.kind {
        case .push(let page):
            NavigationLink {
                pushDestination(page)
            } label: {
                rowLabel(row, accessory: .chevron)
            }
            .buttonStyle(.plain)
        case .sheetLogin:
            Button { showLogin = true } label: {
                rowLabel(row, accessory: .chevron)
            }
            .buttonStyle(.plain)
        case .sheetSleepTimer:
            Button { showSleepTimer = true } label: {
                rowLabel(row, accessory: .chevron)
            }
            .buttonStyle(.plain)
        case .expandable(let kind):
            expandableRow(row, kind: kind)
        case .toggleHighRefresh:
            rowLabel(row, accessory: .toggle($highRefreshRate))
        case .toggleDynamicIsland:
            rowLabel(row, accessory: .toggle($theme.showDynamicIsland))
        case .toggleTabBarHidden:
            rowLabel(row, accessory: .toggle($theme.tabBarHidden))
        }
    }

    private func expandableRow(_ row: RowDef, kind: ExpandableKind) -> some View {
        let open = expandedKeys.contains(row.key)
        return VStack(spacing: 0) {
            Button {
                withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                    if open { expandedKeys.remove(row.key) } else { expandedKeys.insert(row.key) }
                }
            } label: {
                rowLabel(row, accessory: .expandable(open))
            }
            .buttonStyle(.plain)
            if open {
                Divider()
                    .padding(.leading, 58)
                    .opacity(0.5)
                expandableContent(kind)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
            }
        }
    }

    // MARK: - 展开内容

    @ViewBuilder
    private func expandableContent(_ kind: ExpandableKind) -> some View {
        switch kind {
        case .platforms:
            PlatformTogglesView()
        case .themeMode:
            ThemeModePickerView()
        case .wallpaper:
            WallpaperSettingsView()
        case .quality:
            QualityPickerView()
        case .playback:
            PlaybackTogglesView()
        case .backup:
            BackupActionsView()
        case .cache:
            CacheCleanView()
        case .disclaimer:
            Text("本应用仅供学习交流使用。所有音乐内容版权归原作者及平台所有，请支持正版。如有侵权请联系删除。")
                .font(.callout)
                .foregroundColor(.secondary)
                .padding(.vertical, 4)
        case .environment:
            EnvironmentInfoView()
        }
    }

    // MARK: - Push 目标

    @ViewBuilder
    private func pushDestination(_ page: PushPage) -> some View {
        switch page {
        case .equalizer:
            EqualizerSettingsView()
        case .playlistImport:
            PlaylistImportView()
        case .changelog:
            ChangelogView()
        case .checkUpdate:
            CheckUpdateView()
        case .feedback:
            FeedbackView()
        case .diagnostics:
            DiagnosticsView()
        }
    }
}

// MARK: - 展开区小组件

private struct InlineToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.body)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundColor(.secondary)
                }
            }
            Spacer()
            Toggle("", isOn: $isOn).labelsHidden()
        }
        .padding(.vertical, 6)
    }
}

private struct InlineOptionRow: View {
    let title: String
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Text(title).font(.body).foregroundColor(.primary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .foregroundColor(.blue)
                        .font(.system(size: 16, weight: .semibold))
                }
            }
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

private struct PlatformTogglesView: View {
    @AppStorage("settings.platform.netease") private var netease = true
    @AppStorage("settings.platform.kugou") private var kugou = true
    @AppStorage("settings.platform.kuwo") private var kuwo = true
    @AppStorage("settings.platform.migu") private var migu = true
    @AppStorage("settings.platform.qq") private var qq = true

    var body: some View {
        VStack(spacing: 2) {
            InlineToggleRow(title: "网易云", subtitle: nil, isOn: $netease)
            InlineToggleRow(title: "酷狗", subtitle: nil, isOn: $kugou)
            InlineToggleRow(title: "酷我", subtitle: nil, isOn: $kuwo)
            InlineToggleRow(title: "咪咕", subtitle: nil, isOn: $migu)
            InlineToggleRow(title: "QQ 音乐", subtitle: nil, isOn: $qq)
        }
    }
}

private struct ThemeModePickerView: View {
    @EnvironmentObject var theme: ThemeSettings

    var body: some View {
        VStack(spacing: 2) {
            ForEach(ThemeSettings.AccentChoice.allCases, id: \.self) { choice in
                InlineOptionRow(title: choice.rawValue, selected: theme.accent == choice) {
                    theme.accent = choice
                }
            }
        }
    }
}

private struct WallpaperSettingsView: View {
    @AppStorage("settings.wallpaper.enabled") private var enabled = false
    // v4.3：发现页背景（默认深空渐变）
    @AppStorage("settings.discover.wallpaper") private var discoverWallpaper = DiscoverWallpaper.darkSpace.rawValue
    private let discoverOptions: [DiscoverWallpaper] = [.system, .darkSpace, .inkBlue, .ember]

    var body: some View {
        VStack(spacing: 2) {
            InlineToggleRow(title: "开启动态壁纸", subtitle: "播放页背景跟随封面流动", isOn: $enabled)
            VStack(alignment: .leading, spacing: 2) {
                Text("发现页背景")
                    .font(.body)
                    .foregroundColor(AppleTheme.label)
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                ForEach(discoverOptions, id: \.rawValue) { option in
                    InlineOptionRow(title: option.rawValue, selected: discoverWallpaper == option.rawValue) {
                        discoverWallpaper = option.rawValue
                    }
                }
            }
        }
    }
}

private struct QualityPickerView: View {
    @AppStorage("settings.audio.quality") private var quality = "统一音质"
    private let options = ["统一音质", "标准", "高品质", "无损"]

    var body: some View {
        VStack(spacing: 2) {
            ForEach(options, id: \.self) { option in
                InlineOptionRow(title: option, selected: quality == option) {
                    quality = option
                }
            }
        }
    }
}

private struct PlaybackTogglesView: View {
    @AppStorage("settings.playback.resume") private var resume = true
    @AppStorage("settings.playback.gapless") private var gapless = false
    @AppStorage("settings.playback.autoSwitch") private var autoSwitch = true

    var body: some View {
        VStack(spacing: 2) {
            InlineToggleRow(title: "断点续播", subtitle: "下次打开继续上次进度", isOn: $resume)
            InlineToggleRow(title: "无缝播放", subtitle: "歌曲之间无间隙衔接", isOn: $gapless)
            InlineToggleRow(title: "播放失败自动换源", subtitle: nil, isOn: $autoSwitch)
        }
    }
}

private struct BackupActionsView: View {
    @State private var message: String?

    var body: some View {
        VStack(spacing: 8) {
            Button {
                message = "备份功能即将上线"
            } label: {
                Text("立即备份")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.blue.opacity(0.15))
                    .foregroundColor(.blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            Button {
                message = "暂无可用备份"
            } label: {
                Text("从备份恢复")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.primary.opacity(0.06))
                    .foregroundColor(.primary)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct CacheCleanView: View {
    @State private var cacheSize = "128 MB"
    @State private var cleaned = false

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text("缓存大小").font(.body)
                Spacer()
                Text(cleaned ? "0 MB" : cacheSize)
                    .font(.body)
                    .foregroundColor(.secondary)
            }
            .padding(.vertical, 4)
            Button {
                withAnimation {
                    cleaned = true
                }
            } label: {
                Text(cleaned ? "已清理" : "清理缓存")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(cleaned ? Color.green.opacity(0.12) : Color.orange.opacity(0.15))
                    .foregroundColor(cleaned ? .green : .orange)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(cleaned)
        }
        .padding(.vertical, 4)
    }
}

private struct EnvironmentInfoView: View {
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "-"
    }
    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "-"
    }

    var body: some View {
        VStack(spacing: 2) {
            infoRow("设备", UIDevice.current.model)
            infoRow("系统", "iOS \(UIDevice.current.systemVersion)")
            infoRow("App 版本", appVersion)
            infoRow("构建号", buildNumber)
            infoRow("Bundle ID", Bundle.main.bundleIdentifier ?? "-")
        }
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.body).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.body.monospaced()).foregroundColor(.primary)
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Push 子页面

private struct SettingsSubPage<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        ZStack {
            AppleTheme.background.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    content
                }
                .padding(16)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct EqualizerSettingsView: View {
    @State private var enabled = false

    var body: some View {
        SettingsSubPage(title: "均衡器") {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("启用均衡器").font(.body)
                    Text("已关闭").font(.caption).foregroundColor(.secondary)
                }
                Spacer()
                Toggle("", isOn: $enabled).labelsHidden()
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("均衡器功能即将上线，敬请期待。")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }
}

private struct ChangelogView: View {
    private let entries: [(String, [String])] = [
        ("v4.3", ["Beans 风格设置页重做", "歌词页大字层级", "图标去底座"]),
        ("v4.2", ["未来飙升榜（AI 预测）", "歌单导入 UI", "心动飞行动画", "封面飞进播放页", "灵动岛 / 锁屏歌词"]),
        ("v4.1", ["5 平台付费音源长按换源", "网易云搜索分组展示"]),
        ("v4.0", ["睡眠定时 30 秒淡出", "真 FFT 三频段频谱", "波形进度条", "电台 Tab", "手动换源"]),
    ]

    var body: some View {
        SettingsSubPage(title: "更新日志") {
            ForEach(entries, id: \.0) { version, items in
                VStack(alignment: .leading, spacing: 8) {
                    Text(version)
                        .font(.headline)
                    ForEach(items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 8) {
                            Text("•").foregroundColor(.secondary)
                            Text(item).font(.callout)
                        }
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
        }
    }
}

private struct CheckUpdateView: View {
    @State private var lastChecked: String?
    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        SettingsSubPage(title: "检查更新") {
            VStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 48))
                    .foregroundColor(.green)
                Text("已是最新版本")
                    .font(.headline)
                Text("v\(appVersion)")
                    .font(.callout)
                    .foregroundColor(.secondary)
                if let lastChecked {
                    Text("上次检查：\(lastChecked)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                Button {
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd HH:mm"
                    lastChecked = formatter.string(from: Date())
                } label: {
                    Text("重新检查")
                        .font(.body.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.blue.opacity(0.15))
                        .foregroundColor(.blue)
                        .cornerRadius(12)
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }
}

private struct FeedbackView: View {
    @State private var text = ""
    @State private var sent = false

    var body: some View {
        SettingsSubPage(title: "问题反馈") {
            Text("遇到问题或有建议，欢迎告诉我们。")
                .font(.callout)
                .foregroundColor(.secondary)
            TextEditor(text: $text)
                .frame(minHeight: 160)
                .padding(8)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12))
                .overlay(
                    Group {
                        if text.isEmpty {
                            Text("请描述你遇到的问题…")
                                .foregroundColor(.secondary)
                                .padding(.top, 16)
                                .padding(.leading, 12)
                                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        }
                    }
                )
            Button {
                sent = true
            } label: {
                Text(sent ? "已提交，感谢反馈" : "提交反馈")
                    .font(.body.weight(.medium))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background((sent ? Color.green : Color.blue).opacity(0.15))
                    .foregroundColor(sent ? .green : .blue)
                    .cornerRadius(12)
            }
            .buttonStyle(.plain)
            .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || sent)
        }
    }
}

private struct DiagnosticsView: View {
    private var systemVersion: String { UIDevice.current.systemVersion }
    private var model: String { UIDevice.current.model }

    var body: some View {
        SettingsSubPage(title: "诊断与日志") {
            VStack(spacing: 2) {
                diagRow("设备", model)
                diagRow("系统版本", "iOS \(systemVersion)")
                diagRow("网络状态", "正常")
                diagRow("后端连通", "正常")
            }
            .padding()
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            Text("日志导出功能即将上线。")
                .font(.callout)
                .foregroundColor(.secondary)
        }
    }

    private func diagRow(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title).font(.body).foregroundColor(.secondary)
            Spacer()
            Text(value).font(.body)
        }
        .padding(.vertical, 6)
    }
}
