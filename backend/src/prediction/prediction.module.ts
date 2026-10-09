import { Module } from '@nestjs/common';
import { TypeOrmModule } from '@nestjs/typeorm';
import { PlayEvent } from '../entities/play-event.entity';
import { Track } from '../entities/track.entity';
import { PredictionService } from './prediction.service';

@Module({
  imports: [TypeOrmModule.forFeature([Track, PlayEvent])],
  providers: [PredictionService],
  exports: [PredictionService],
})
export class PredictionModule {}
