import { Controller, Delete, HttpCode } from '@nestjs/common';
import { AuthService } from '../auth/auth.service';
import {
  AuthUser,
  CurrentUser,
} from '../common/decorators/current-user.decorator';

@Controller('account')
export class AccountController {
  constructor(private readonly authService: AuthService) {}

  /**
   * 账号注销闭环（Apple Guideline 5.1.1(v)）：
   * 软删除用户 + 吊销全部 refresh token。
   */
  @Delete()
  @HttpCode(200)
  deleteAccount(@CurrentUser() user: AuthUser) {
    return this.authService.deleteAccount(user.id);
  }
}
