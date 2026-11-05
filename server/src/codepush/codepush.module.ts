import { Module } from '@nestjs/common';
import { AccessService } from './access.service';
import { AdminController } from './admin.controller';
import { CodePushController } from './codepush.controller';
import { PatchCheckService } from './patch-check.service';
import { UpdaterController } from './updater.controller';

@Module({
  controllers: [UpdaterController, CodePushController, AdminController],
  providers: [AccessService, PatchCheckService],
  exports: [AccessService, PatchCheckService],
})
export class CodePushModule {}
