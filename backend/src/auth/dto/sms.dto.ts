import { IsString, Matches, MaxLength } from 'class-validator';

export const PHONE_REGEX = /^1\d{10}$/;

export class SmsSendDto {
  @IsString()
  @Matches(PHONE_REGEX, { message: '手机号格式不正确' })
  phone: string;
}

export class SmsVerifyDto {
  @IsString()
  @Matches(PHONE_REGEX, { message: '手机号格式不正确' })
  phone: string;

  @IsString()
  @MaxLength(16)
  code: string;
}
