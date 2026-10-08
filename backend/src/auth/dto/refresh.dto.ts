import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class RefreshDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  refreshToken: string;
}
