import { Module } from '@nestjs/common';
import { CodePushModule } from '../codepush/codepush.module';
import { DashboardController } from './dashboard.controller';

@Module({ imports: [CodePushModule], controllers: [DashboardController] })
export class DashboardModule {}
