import {
  Column,
  CreateDateColumn,
  Entity,
  OneToMany,
  PrimaryGeneratedColumn,
  UpdateDateColumn,
} from 'typeorm';
import { TrackSource } from './track-source.entity';

export const TRACK_STATUS_ONLINE = 'online';
export const TRACK_STATUS_OFFLINE = 'offline';

/** 手动换源：用户锁定的播放源（lx-music 手动换源的服务端版） */
export const SOURCE_AUTO = 'auto';
export const SOURCE_LOCAL = 'local';
export const VALID_SOURCES = ['auto', 'local', 'netease', 'qq', 'kugou'] as const;
export type PreferredSource = (typeof VALID_SOURCES)[number];

@Entity('tracks')
export class Track {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ type: 'varchar', length: 255 })
  title: string;

  @Column({ type: 'varchar', length: 255 })
  artist: string;

  @Column({ type: 'varchar', length: 255, nullable: true })
  album: string | null;

  @Column({ name: 'cover_url', type: 'text', nullable: true })
  coverUrl: string | null;

  @Column({ name: 'duration_ms', type: 'integer', default: 0 })
  durationMs: number;

  @Column({ name: 'lrc_text', type: 'text', nullable: true })
  lrcText: string | null;

  @Column({ name: 'lrc_synced', type: 'boolean', default: false })
  lrcSynced: boolean;

  @Column({ name: 'play_count', type: 'bigint', default: 0 })
  playCount: string;

  @Column({ type: 'varchar', length: 16, default: TRACK_STATUS_ONLINE })
  status: string;

  @Column({ name: 'preferred_source', type: 'varchar', length: 16, default: SOURCE_AUTO })
  preferredSource: string;

  @OneToMany(() => TrackSource, (source) => source.track)
  sources: TrackSource[];

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;

  @UpdateDateColumn({ name: 'updated_at', type: 'timestamptz' })
  updatedAt: Date;
}
