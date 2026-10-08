import { IsIn, IsOptional } from 'class-validator';
import { TRACK_QUALITIES } from '../../entities/track-source.entity';

export class StreamQueryDto {
  @IsOptional()
  @IsIn([...TRACK_QUALITIES], { message: 'quality 仅支持 standard|high|lossless|hires' })
  quality = 'high';
}
