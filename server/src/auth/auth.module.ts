import { Global, Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { config } from '../config';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { ApiKeyGuard, SessionGuard } from './guards';

@Global()
@Module({
  imports: [JwtModule.register({ secret: config.jwtSecret })],
  controllers: [AuthController],
  providers: [AuthService, ApiKeyGuard, SessionGuard],
  exports: [AuthService, ApiKeyGuard, SessionGuard],
})
export class AuthModule {}
