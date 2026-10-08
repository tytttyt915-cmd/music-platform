import { Injectable, UnauthorizedException } from '@nestjs/common';
import { PassportStrategy } from '@nestjs/passport';
import { ConfigService } from '@nestjs/config';
import { InjectRepository } from '@nestjs/typeorm';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { Repository } from 'typeorm';
import { User, USER_STATUS_ACTIVE } from '../entities/user.entity';

export interface JwtPayload {
  sub: string; // user id
  isGuest: boolean;
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    @InjectRepository(User)
    private readonly usersRepo: Repository<User>,
  ) {
    const secret = config.get<string>('jwt.secret', '');
    if (!secret) {
      throw new Error(
        'JWT_SECRET 未配置：请在环境变量中设置 JWT_SECRET（生产环境必须为强随机串）后重启',
      );
    }
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: secret,
    });
  }

  async validate(payload: JwtPayload) {
    const user = await this.usersRepo.findOne({
      where: { id: payload.sub, status: USER_STATUS_ACTIVE },
      select: ['id', 'unionid', 'phone', 'isGuest', 'status'],
    });
    if (!user) {
      throw new UnauthorizedException('用户不存在或已被注销');
    }
    return {
      id: user.id,
      isGuest: payload.isGuest ?? user.isGuest,
      unionid: user.unionid,
      phone: user.phone,
    };
  }
}
