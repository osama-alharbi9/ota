import './config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import cookieParser from 'cookie-parser';
import { json } from 'express';
import { AppModule } from './app.module';
import { AllExceptionsFilter } from './common/exception.filter';
import { config } from './config';

async function bootstrap() {
  const app = await NestFactory.create<NestExpressApplication>(AppModule, { logger: ['error', 'warn', 'log'] });
  app.use(cookieParser());
  // The ota CLI posts JSON with a text/plain content type, so parse any
  // body as JSON except uploads (multipart) and raw binary.
  app.use(
    json({
      limit: '5mb',
      type: (req) => {
        const ct = String(req.headers['content-type'] ?? '');
        return !ct.startsWith('multipart/') && !ct.startsWith('application/octet-stream');
      },
    }),
  );
  app.enableCors({ origin: [config.webOrigin], credentials: true });
  app.useGlobalFilters(new AllExceptionsFilter());
  app.getHttpAdapter().getInstance().set('etag', false);
  app.getHttpAdapter().getInstance().disable('x-powered-by');
  // One JSON line per request, so any log collector can parse it. No client IPs.
  app.use((req: import('express').Request, res: import('express').Response, next: () => void) => {
    const start = Date.now();
    res.on('finish', () => {
      console.log(
        JSON.stringify({
          time: new Date().toISOString(),
          msg: 'request',
          method: req.method,
          path: req.originalUrl,
          status: res.statusCode,
          ms: Date.now() - start,
          ua: req.headers['user-agent'] ?? null,
          cli: req.headers['x-cli-version'] ?? null,
        }),
      );
    });
    next();
  });
  app.getHttpAdapter().getInstance().get('/healthz', (_req: import('express').Request, res: import('express').Response) => res.send('ok'));
  await app.listen(config.port, '0.0.0.0');
  console.log(`ota-api listening on :${config.port}, public URL ${config.publicUrl}`);
}
void bootstrap();
