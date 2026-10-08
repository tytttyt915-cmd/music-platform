import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { Request, Response } from 'express';

@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  private readonly logger = new Logger('ExceptionFilter');

  catch(exception: unknown, host: ArgumentsHost) {
    const ctx = host.switchToHttp();
    const response = ctx.getResponse<Response>();
    const request = ctx.getRequest<Request>();

    let status = HttpStatus.INTERNAL_SERVER_ERROR;
    let message = '服务器内部错误';

    if (exception instanceof HttpException) {
      status = exception.getStatus();
      const res = exception.getResponse();
      if (typeof res === 'string') {
        message = res;
      } else if (res && typeof res === 'object') {
        const msg = (res as Record<string, unknown>).message;
        message = Array.isArray(msg)
          ? msg.join('; ')
          : String(msg ?? exception.message);
      }
    } else {
      this.logger.error(
        `Unhandled exception: ${request.method} ${request.url}`,
        exception instanceof Error ? exception.stack : String(exception),
      );
    }

    // 对已发送的响应（例如 res.redirect）不再重复写
    if (response.headersSent) return;

    // code: 业务错误码 —— 与 HTTP 状态码保持一致，方便客户端统一处理
    response.status(status).json({
      code: status,
      message,
      data: null,
    });
  }
}
