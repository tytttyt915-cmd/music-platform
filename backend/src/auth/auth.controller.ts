import { Body, Controller, Delete, HttpCode, Post } from '@nestjs/common';
import { AuthService } from './auth.service';
import { RefreshDto } from './dto/refresh.dto';
import { SmsSendDto, SmsVerifyDto } from './dto/sms.dto';
import { WechatLoginDto } from './dto/wechat-login.dto';
import { Public } from '../common/decorators/public.decorator';
import { CurrentUser, AuthUser } from '../common/decorators/current-user.decorator';

@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Public()
  @Post('wechat/login')
  @HttpCode(200)
  wechatLogin(@Body() dto: WechatLoginDto) {
    return this.authService.wechatLogin(dto.code);
  }

  @Public()
  @Post('sms/send')
  @HttpCode(200)
  sendSms(@Body() dto: SmsSendDto) {
    return this.authService.sendSmsCode(dto.phone);
  }

  @Public()
  @Post('sms/verify')
  @HttpCode(200)
  verifySms(@Body() dto: SmsVerifyDto) {
    return this.authService.verifySmsCode(dto.phone, dto.code);
  }

  /** 纯净游客试听模式：未登录也可签发 token（Guideline 5.1.1） */
  @Public()
  @Post('guest')
  @HttpCode(200)
  guest() {
    return this.authService.guestLogin();
  }

  @Public()
  @Post('refresh')
  @HttpCode(200)
  refresh(@Body() dto: RefreshDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @Post('logout')
  @HttpCode(200)
  logout(@CurrentUser() user: AuthUser, @Body() dto: RefreshDto) {
    return this.authService.logout(user.id, dto.refreshToken);
  }
}
