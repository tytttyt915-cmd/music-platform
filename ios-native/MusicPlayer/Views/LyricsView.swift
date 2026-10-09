import SwiftUI

// Views 适配（2026-10-09）：songId Int → String（UUID）；api.lyrics(for:) → music.lyrics(id:)
struct LyricsView: View {
    let songId: String
    @EnvironmentObject var music: MusicService
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings
    @State private var lines: [LyricLine] = []
    @State private var isLoading = false
    
    var body: some View {
        Group {
            if isLoading {
                ProgressView()
            } else if lines.isEmpty {
                Text("暂无歌词")
                    .foregroundColor(theme.secondaryTextColor)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 12) {
                            ForEach(lines) { line in
                                Text(line.text)
                                    .font(.system(size: isCurrent(line) ? 18 : 15))
                                    .fontWeight(isCurrent(line) ? .bold : .regular)
                                    .foregroundColor(isCurrent(line) ? theme.accentColor : theme.textColor.opacity(0.7))
                                    .id(line.id)
                            }
                        }
                        .padding()
                    }
                    .onChange(of: currentIndex) { idx in
                        if idx >= 0 && idx < lines.count {
                            withAnimation {
                                proxy.scrollTo(lines[idx].id, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
        .onAppear { load() }
    }
    
    private var currentIndex: Int {
        let t = player.currentTime
        var idx = -1
        for (i, line) in lines.enumerated() {
            if line.time <= t { idx = i } else { break }
        }
        return idx
    }
    
    private func isCurrent(_ line: LyricLine) -> Bool {
        guard let idx = lines.firstIndex(where: { $0.id == line.id }) else { return false }
        return idx == currentIndex
    }
    
    private func load() {
        isLoading = true
        Task {
            do {
                let result = try await music.lyrics(id: songId)
                await MainActor.run {
                    lines = result
                    isLoading = false
                }
            } catch {
                await MainActor.run { isLoading = false }
            }
        }
    }
}
