import {
  Column,
  CreateDateColumn,
  Entity,
  JoinColumn,
  ManyToOne,
  PrimaryGeneratedColumn,
} from 'typeorm';
import { Track } from './track.entity';

export const TRACK_QUALITIES = [
  'standard',
  'high',
  'lossless',
  'hires',
] as const;
export type TrackQuality = (typeof TRACK_QUALITIES)[number];

@Entity('track_sources')
export class TrackSource {
  @PrimaryGeneratedColumn('uuid')
  id: string;

  @Column({ name: 'track_id', type: 'uuid' })
  trackId: string;

  @Column({ type: 'varchar', length: 16 })
  quality: string;

  @Column({ name: 'bitrate_kbps', type: 'integer' })
  bitrateKbps: number;

  @Column({ name: 'sample_rate_hz', type: 'integer', nullable: true })
  sampleRateHz: number | null;

  @Column({ name: 'file_size_bytes', type: 'bigint', nullable: true })
  fileSizeBytes: string | null;

  @Column({ name: 'storage_key', type: 'text' })
  storageKey: string;

  @Column({ name: 'duration_ms', type: 'integer', default: 0 })
  durationMs: number;

  @ManyToOne(() => Track, (track) => track.sources, { onDelete: 'CASCADE' })
  @JoinColumn({ name: 'track_id' })
  track: Track;

  @CreateDateColumn({ name: 'created_at', type: 'timestamptz' })
  createdAt: Date;
}
