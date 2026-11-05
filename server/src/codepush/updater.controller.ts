import { Body, Controller, Get, HttpCode, Param, Post, Req, Res } from '@nestjs/common';
import { Request, Response } from 'express';
import { ApiError } from '../common/api-error';
import { PrismaService } from '../prisma/prisma.service';
import { StorageService } from '../storage/storage.service';
import { PatchCheckRequest, PatchCheckService } from './patch-check.service';

/** Endpoints the on-device updater calls. Unauthenticated, like upstream. */
@Controller('api/v1')
export class UpdaterController {
  constructor(
    private readonly prisma: PrismaService,
    private readonly storage: StorageService,
    private readonly patchCheck: PatchCheckService,
  ) {}

  @Post('patches/check')
  @HttpCode(200)
  async check(@Body() body: PatchCheckRequest) {
    for (const k of ['app_id', 'channel', 'release_version', 'platform', 'arch'] as const) {
      if (typeof body?.[k] !== 'string') throw ApiError.badRequest(`Missing field ${k}.`);
    }
    const response = await this.patchCheck.compute(body);
    await this.prisma.patchCheck.create({ data: { appId: body.app_id, request: body as object, response: response as object } });
    console.log(`patch check ${JSON.stringify(body)} => ${JSON.stringify(response)}`);
    return response;
  }

  @Post('patches/events')
  @HttpCode(201)
  async event(@Body() body: { event?: { app_id?: string } }) {
    await this.prisma.patchEvent.create({ data: { appId: body?.event?.app_id ?? null, event: (body ?? {}) as object } });
    console.log(`patch event ${JSON.stringify(body)}`);
    return {};
  }

  /** Capability URL: anyone holding the token can download. Exact Content-Length
   *  matters: the updater discards the download if it differs. */
  @Get('artifacts/:kind/:token')
  async download(@Param('kind') kind: string, @Param('token') token: string, @Req() req: Request, @Res() res: Response) {
    const row =
      kind === 'release'
        ? await this.prisma.releaseArtifact.findFirst({ where: { downloadToken: token, uploaded: true } })
        : kind === 'patch'
          ? await this.prisma.patchArtifact.findFirst({ where: { downloadToken: token, uploaded: true } })
          : null;
    if (!row) throw ApiError.notFound('Unknown download URL.');
    const { body } = await this.storage.getStream(row.storageKey);
    res.status(200);
    res.setHeader('content-type', 'application/octet-stream');
    res.setHeader('content-length', String(row.size));
    body.on('error', (e) => {
      console.error('download stream error', e);
      res.destroy(e);
    });
    req.on('close', () => body.destroy());
    body.pipe(res);
  }
}
