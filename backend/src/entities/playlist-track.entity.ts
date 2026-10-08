import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryColumn,
} from 'typeorm';
import { Playlist } from './playlist.entity';
import { Track } from './track.entity';

@Entity('playlist_tracks')
export class PlaylistTrack {
  @PrimaryColumn({ name: 'playlist_id', type: 'uuid' })
  playlistId: string;

  @PrimaryColumn({ name: 'track_id', type: 'uuid' })
  trackId: string;

  @Column({ type: 'integer', default: 0 })
  position: number;

  @CreateDateColumn({ name: 'added_at', type: 'timestamptz' })
  addedAt: Date;

  @ManyToOne(() => Playlist, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'playlist_id' })
  playlist: Playlist;

  @ManyToOne(() => Track, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'track_id' })
  track: Track;
}
