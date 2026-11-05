import * as path from 'path';
import * as dotenv from 'dotenv';

// Local development reads the repo's .env (same file docker-compose uses).
// Inside the container the variables are already set, so this is a no-op.
dotenv.config({ path: path.resolve(__dirname, '../../../.env'), override: false });
dotenv.config({ path: path.resolve(__dirname, '../.env'), override: false });

const env = process.env;
const req = (k: string): string => {
  const v = env[k];
  if (!v) throw new Error(`Missing required environment variable ${k}`);
  return v;
};

const publicUrl = (env.PUBLIC_URL ?? 'http://localhost:8080').replace(/\/+$/, '');

export const config = {
  port: Number(env.PORT ?? 8080),
  publicUrl,
  webOrigin: env.WEB_ORIGIN ?? 'http://localhost:3000',
  jwtSecret: env.JWT_SECRET ?? env.API_TOKEN ?? 'dev-only-change-me',
  cookieName: 'ota_session',
  databaseUrl:
    env.DATABASE_URL ??
    `postgresql://${env.DB_USER ?? 'ota'}:${encodeURIComponent(req('DB_PASSWORD'))}@${env.DB_HOST ?? 'localhost'}:${env.DB_PORT ?? 5432}/${env.DB_NAME ?? 'ota'}`,
  s3: {
    endpoint: `${env.S3_USE_SSL === 'true' ? 'https' : 'http'}://${env.S3_ENDPOINT ?? 'localhost'}:${env.S3_PORT ?? 9000}`,
    // MinIO and SeaweedFS want path-style URLs and accept any region; hosted S3
    // services may want their own region and virtual-hosted URLs.
    region: env.S3_REGION ?? 'us-east-1',
    forcePathStyle: env.S3_FORCE_PATH_STYLE !== 'false',
    accessKey: req('S3_ACCESS_KEY'),
    secretKey: req('S3_SECRET_KEY'),
    bucket: env.S3_BUCKET ?? 'ota-artifacts',
  },
  bootstrap: {
    email: env.BOOTSTRAP_EMAIL,
    password: env.BOOTSTRAP_PASSWORD,
    apiToken: env.API_TOKEN, // pre-shared key from .env; registered as a real key for the bootstrap admin
  },
};
process.env.DATABASE_URL = config.databaseUrl;
