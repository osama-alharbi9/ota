import { ArgumentsHost, Catch, ExceptionFilter, HttpException } from '@nestjs/common';
import { Response } from 'express';

/** Every error leaves the server as `{code, message, details}`. */
@Catch()
export class AllExceptionsFilter implements ExceptionFilter {
  catch(exception: unknown, host: ArgumentsHost) {
    const res = host.switchToHttp().getResponse<Response>();
    const req = host.switchToHttp().getRequest<{ method: string; url: string }>();
    if (exception instanceof HttpException) {
      const status = exception.getStatus();
      const body = exception.getResponse() as Record<string, unknown> | string;
      if (typeof body === 'object' && body && 'code' in body) {
        return res.status(status).json(body);
      }
      const message =
        typeof body === 'string' ? body : ((body as { message?: string | string[] }).message ?? exception.message);
      return res.status(status).json({
        code: status === 404 ? 'not_found' : status === 401 ? 'unauthorized' : status === 403 ? 'forbidden' : 'error',
        message: Array.isArray(message) ? message.join('; ') : message,
        details: null,
      });
    }
    const err = exception as Error;
    console.error(`Unhandled error on ${req.method} ${req.url}:`, err?.stack ?? err);
    return res.status(500).json({ code: 'internal_error', message: 'Internal server error.', details: err?.message ?? null });
  }
}
