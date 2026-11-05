import { Injectable, OnModuleDestroy, OnModuleInit } from '@nestjs/common';
import { PrismaClient } from '@prisma/client';

@Injectable()
export class PrismaService extends PrismaClient implements OnModuleInit, OnModuleDestroy {
  async onModuleInit() {
    for (let attempt = 1; ; attempt++) {
      try {
        await this.$connect();
        return;
      } catch (e) {
        if (attempt >= 30) throw e;
        console.log(`Waiting for database (${attempt}): ${(e as Error).message}`);
        await new Promise((r) => setTimeout(r, 1000));
      }
    }
  }
  async onModuleDestroy() {
    await this.$disconnect();
  }
}
