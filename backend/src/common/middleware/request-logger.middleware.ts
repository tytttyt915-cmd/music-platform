import { Injectable, Logger, NestMiddleware } from '@nestjs/common';
import { NextFunction, Request, Response } from 'express';

@Injectable()
export class RequestLoggerMiddleware implements NestMiddleware {
  private readonly logger = new Logger('HTTP');

  use(req: Request, res: Response, next: NextFunction) {
    const startedAt = Date.now();
    const { method, originalUrl, ip } = req;

    res.on('finish', () => {
      const durationMs = Date.now() - startedAt;
      const { statusCode } = res;
      this.logger.log(
        `${method} ${originalUrl} ${statusCode} ${durationMs}ms - ${ip}`,
      );
    });

    next();
  }
}
