import * as crypto from 'crypto';
import * as fs from 'fs';
import busboy from 'busboy';
import { Request } from 'express';
import { ApiError } from './api-error';

export interface MultipartResult {
  fields: Record<string, string>;
  fileBytes?: number;
  fileSha256?: string;
}

/** Streams a multipart/form-data request. The single file part is written to
 *  `saveFileTo` when given, otherwise drained. Text fields are returned. */
export function parseMultipart(req: Request, saveFileTo?: string): Promise<MultipartResult> {
  return new Promise((resolve, reject) => {
    const ct = req.headers['content-type'] ?? '';
    if (!ct.startsWith('multipart/form-data')) {
      return reject(ApiError.badRequest('Expected multipart/form-data.'));
    }
    const bb = busboy({ headers: req.headers, limits: { fileSize: 2 * 1024 * 1024 * 1024 } });
    const fields: Record<string, string> = {};
    let fileBytes: number | undefined;
    let fileSha256: string | undefined;
    const pending: Promise<void>[] = [];
    bb.on('field', (name, value) => {
      fields[name] = value;
    });
    bb.on('file', (_name, stream) => {
      if (!saveFileTo) {
        stream.resume();
        return;
      }
      const hash = crypto.createHash('sha256');
      let count = 0;
      const out = fs.createWriteStream(saveFileTo);
      stream.on('data', (chunk: Buffer) => {
        count += chunk.length;
        hash.update(chunk);
      });
      stream.pipe(out);
      pending.push(
        new Promise<void>((res, rej) => {
          out.on('finish', () => {
            fileBytes = count;
            fileSha256 = hash.digest('hex');
            res();
          });
          out.on('error', rej);
          stream.on('error', rej);
        }),
      );
    });
    bb.on('error', reject);
    bb.on('close', () => {
      Promise.all(pending)
        .then(() => resolve({ fields, fileBytes, fileSha256 }))
        .catch(reject);
    });
    req.pipe(bb);
  });
}
