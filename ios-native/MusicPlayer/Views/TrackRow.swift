import SwiftUI

struct TrackRow: View {
    let track: Track
    @EnvironmentObject var player: AudioPlayerManager
    @EnvironmentObject var theme: ThemeSettings
    
    var body: some View {
        Button { player.playTracks([track], startAt: 0) } label: {
            HStack {
                VStack(alignment: .leading) {
                    Text(track.title).foregroundColor(theme.textColor)
                    Text(track.artist).font(.caption).foregroundColor(theme.secondaryTextColor)
                }
                Spacer()
                if player.currentTrack?.id == track.id {
                    Image(systemName: "waveform").foregroundColor(theme.accentColor)
                }
            }
            .padding(.vertical, 6)
        }
    }
}
