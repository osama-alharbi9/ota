import { Module } from '@nestjs/common';
import { AuthModule } from './auth/auth.module';
import { BootstrapService } from './bootstrap.service';
import { CodePushModule } from './codepush/codepush.module';
import { DashboardModule } from './dashboard/dashboard.module';
import { PrismaModule } from './prisma/prisma.module';
import { StorageModule } from './storage/storage.module';

@Module({
  imports: [PrismaModule, StorageModule, AuthModule, CodePushModule, DashboardModule],
  providers: [BootstrapService],
})
export class AppModule {}
