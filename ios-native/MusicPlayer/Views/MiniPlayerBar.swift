import SwiftUI

struct MiniPlayerBar: View {
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings
    var onTap: () -> Void
    
    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 0) {
                HStack {
                    if let track = player.currentTrack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title)
                                .font(Font.subheadline)
                                .foregroundColor(theme.textColor)
                                .lineLimit(1)
                            Text(track.artist)
                                .font(.caption)
                                .foregroundColor(theme.secondaryTextColor)
                                .lineLimit(1)
                        }
                        Spacer()
                        Button {
                            player.togglePlayPause()
                        } label: {
                            Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
                                .foregroundColor(theme.textColor)
                                .font(.title3)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                
                // 进度条
                if player.duration > 0 {
                    GeometryReader { geo in
                        Rectangle()
                            .fill(theme.accentColor)
                            .frame(width: geo.size.width * CGFloat(player.currentTime / player.duration), height: 2)
                    }
                    .frame(height: 2)
                }
            }
            .background(Color.gray.opacity(0.15))
            .cornerRadius(12)
        }
        .buttonStyle(.plain)
    }
}
