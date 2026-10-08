import { IsNotEmpty, IsString, MaxLength } from 'class-validator';

export class WechatLoginDto {
  @IsString()
  @IsNotEmpty()
  @MaxLength(128)
  code: string;
}
