import {
  IsBoolean,
  IsNotEmpty,
  IsOptional,
  IsString,
  IsUrl,
  MaxLength,
} from 'class-validator';

export class CreatePlaylistDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(255)
  title: string;

  @IsOptional()
  @IsUrl({}, { message: 'coverUrl 必须是合法 URL' })
  coverUrl?: string;

  @IsOptional()
  @IsBoolean()
  isPublic?: boolean;
}
