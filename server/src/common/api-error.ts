import { HttpException } from '@nestjs/common';

/** Error with the `{code, message, details}` body the ota CLI expects. */
export class ApiError extends HttpException {
  constructor(status: number, code: string, message: string, details?: string) {
    super({ code, message, details: details ?? null }, status);
  }
  static notFound(message: string) {
    return new ApiError(404, 'not_found', message);
  }
  static badRequest(message: string, details?: string) {
    return new ApiError(400, 'bad_request', message, details);
  }
  static unauthorized(message = 'Missing or invalid credentials.') {
    return new ApiError(401, 'unauthorized', message);
  }
}
