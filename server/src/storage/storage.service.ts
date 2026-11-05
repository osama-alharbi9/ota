import { Injectable, OnModuleInit } from '@nestjs/common';
import { CreateBucketCommand, GetObjectCommand, HeadBucketCommand, S3Client } from '@aws-sdk/client-s3';
import { Upload } from '@aws-sdk/lib-storage';
import * as fs from 'fs';
import { Readable } from 'stream';
import { config } from '../config';

@Injectable()
export class StorageService implements OnModuleInit {
  private readonly s3 = new S3Client({
    endpoint: config.s3.endpoint,
    region: config.s3.region,
    forcePathStyle: config.s3.forcePathStyle,
    credentials: { accessKeyId: config.s3.accessKey, secretAccessKey: config.s3.secretKey },
  });
  readonly bucket = config.s3.bucket;

  async onModuleInit() {
    for (let attempt = 1; ; attempt++) {
      try {
        try {
          await this.s3.send(new HeadBucketCommand({ Bucket: this.bucket }));
        } catch {
          await this.s3.send(new CreateBucketCommand({ Bucket: this.bucket }));
        }
        return;
      } catch (e) {
        if (attempt >= 30) throw e;
        console.log(`Waiting for object storage (${attempt}): ${(e as Error).message}`);
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
  }

  async putFile(key: string, path: string) {
    const upload = new Upload({
      client: this.s3,
      params: { Bucket: this.bucket, Key: key, Body: fs.createReadStream(path) },
    });
    await upload.done();
  }

  async getStream(key: string): Promise<{ body: Readable; length?: number }> {
    const res = await this.s3.send(new GetObjectCommand({ Bucket: this.bucket, Key: key }));
    return { body: res.Body as Readable, length: res.ContentLength };
  }
}
