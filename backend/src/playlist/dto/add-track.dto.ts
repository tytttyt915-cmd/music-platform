import { IsUUID } from 'class-validator';

export class AddTrackDto {
  @IsUUID('4')
  trackId: string;
}
