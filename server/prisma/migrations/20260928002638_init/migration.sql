-- CreateEnum
CREATE TYPE "OrganizationType" AS ENUM ('personal', 'team');

-- CreateEnum
CREATE TYPE "Role" AS ENUM ('owner', 'admin', 'appManager', 'developer', 'viewer');

-- CreateTable
CREATE TABLE "users" (
    "id" SERIAL NOT NULL,
    "email" TEXT NOT NULL,
    "password_hash" TEXT NOT NULL,
    "display_name" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "users_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "organizations" (
    "id" SERIAL NOT NULL,
    "name" TEXT NOT NULL,
    "type" "OrganizationType" NOT NULL DEFAULT 'personal',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "organizations_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "memberships" (
    "user_id" INTEGER NOT NULL,
    "organization_id" INTEGER NOT NULL,
    "role" "Role" NOT NULL DEFAULT 'developer',

    CONSTRAINT "memberships_pkey" PRIMARY KEY ("user_id","organization_id")
);

-- CreateTable
CREATE TABLE "api_keys" (
    "id" SERIAL NOT NULL,
    "user_id" INTEGER NOT NULL,
    "name" TEXT NOT NULL,
    "key_hash" TEXT NOT NULL,
    "key_prefix" TEXT NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "last_used_at" TIMESTAMP(3),
    "revoked_at" TIMESTAMP(3),

    CONSTRAINT "api_keys_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "apps" (
    "id" TEXT NOT NULL,
    "display_name" TEXT NOT NULL,
    "organization_id" INTEGER NOT NULL,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "apps_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "channels" (
    "id" SERIAL NOT NULL,
    "app_id" TEXT NOT NULL,
    "name" TEXT NOT NULL,

    CONSTRAINT "channels_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "releases" (
    "id" SERIAL NOT NULL,
    "app_id" TEXT NOT NULL,
    "version" TEXT NOT NULL,
    "flutter_revision" TEXT NOT NULL,
    "flutter_version" TEXT,
    "display_name" TEXT,
    "notes" TEXT,
    "platform_statuses" JSONB NOT NULL DEFAULT '{}',
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "releases_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "release_artifacts" (
    "id" SERIAL NOT NULL,
    "release_id" INTEGER NOT NULL,
    "arch" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "hash" TEXT NOT NULL,
    "size" BIGINT NOT NULL,
    "filename" TEXT,
    "can_sideload" BOOLEAN NOT NULL DEFAULT false,
    "podfile_lock_hash" TEXT,
    "storage_key" TEXT NOT NULL,
    "upload_token" TEXT NOT NULL,
    "download_token" TEXT NOT NULL,
    "uploaded" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "release_artifacts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patches" (
    "id" SERIAL NOT NULL,
    "release_id" INTEGER NOT NULL,
    "number" INTEGER NOT NULL,
    "notes" TEXT,
    "metadata" JSONB NOT NULL DEFAULT '{}',
    "is_rolled_back" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "patches_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patch_artifacts" (
    "id" SERIAL NOT NULL,
    "patch_id" INTEGER NOT NULL,
    "arch" TEXT NOT NULL,
    "platform" TEXT NOT NULL,
    "hash" TEXT NOT NULL,
    "hash_signature" TEXT,
    "size" BIGINT NOT NULL,
    "podfile_lock_hash" TEXT,
    "storage_key" TEXT NOT NULL,
    "upload_token" TEXT NOT NULL,
    "download_token" TEXT NOT NULL,
    "uploaded" BOOLEAN NOT NULL DEFAULT false,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "patch_artifacts_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patch_channels" (
    "patch_id" INTEGER NOT NULL,
    "channel_id" INTEGER NOT NULL,
    "promoted_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,

    CONSTRAINT "patch_channels_pkey" PRIMARY KEY ("patch_id","channel_id")
);

-- CreateTable
CREATE TABLE "patch_events" (
    "id" BIGSERIAL NOT NULL,
    "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "app_id" TEXT,
    "event" JSONB NOT NULL,

    CONSTRAINT "patch_events_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "patch_checks" (
    "id" BIGSERIAL NOT NULL,
    "received_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "app_id" TEXT,
    "request" JSONB NOT NULL,
    "response" JSONB NOT NULL,

    CONSTRAINT "patch_checks_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "audit_log" (
    "id" BIGSERIAL NOT NULL,
    "at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "user_id" INTEGER,
    "organization_id" INTEGER,
    "action" TEXT NOT NULL,
    "target" JSONB NOT NULL,

    CONSTRAINT "audit_log_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "users_email_key" ON "users"("email");

-- CreateIndex
CREATE UNIQUE INDEX "api_keys_key_hash_key" ON "api_keys"("key_hash");

-- CreateIndex
CREATE UNIQUE INDEX "channels_app_id_name_key" ON "channels"("app_id", "name");

-- CreateIndex
CREATE UNIQUE INDEX "releases_app_id_version_key" ON "releases"("app_id", "version");

-- CreateIndex
CREATE UNIQUE INDEX "release_artifacts_upload_token_key" ON "release_artifacts"("upload_token");

-- CreateIndex
CREATE UNIQUE INDEX "release_artifacts_download_token_key" ON "release_artifacts"("download_token");

-- CreateIndex
CREATE UNIQUE INDEX "release_artifacts_release_id_arch_platform_key" ON "release_artifacts"("release_id", "arch", "platform");

-- CreateIndex
CREATE UNIQUE INDEX "patches_release_id_number_key" ON "patches"("release_id", "number");

-- CreateIndex
CREATE UNIQUE INDEX "patch_artifacts_upload_token_key" ON "patch_artifacts"("upload_token");

-- CreateIndex
CREATE UNIQUE INDEX "patch_artifacts_download_token_key" ON "patch_artifacts"("download_token");

-- CreateIndex
CREATE UNIQUE INDEX "patch_artifacts_patch_id_arch_platform_key" ON "patch_artifacts"("patch_id", "arch", "platform");

-- CreateIndex
CREATE INDEX "patch_events_app_id_received_at_idx" ON "patch_events"("app_id", "received_at");

-- CreateIndex
CREATE INDEX "patch_checks_app_id_received_at_idx" ON "patch_checks"("app_id", "received_at");

-- CreateIndex
CREATE INDEX "audit_log_organization_id_at_idx" ON "audit_log"("organization_id", "at");

-- AddForeignKey
ALTER TABLE "memberships" ADD CONSTRAINT "memberships_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "memberships" ADD CONSTRAINT "memberships_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "api_keys" ADD CONSTRAINT "api_keys_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "apps" ADD CONSTRAINT "apps_organization_id_fkey" FOREIGN KEY ("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "channels" ADD CONSTRAINT "channels_app_id_fkey" FOREIGN KEY ("app_id") REFERENCES "apps"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "releases" ADD CONSTRAINT "releases_app_id_fkey" FOREIGN KEY ("app_id") REFERENCES "apps"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "release_artifacts" ADD CONSTRAINT "release_artifacts_release_id_fkey" FOREIGN KEY ("release_id") REFERENCES "releases"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patches" ADD CONSTRAINT "patches_release_id_fkey" FOREIGN KEY ("release_id") REFERENCES "releases"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patch_artifacts" ADD CONSTRAINT "patch_artifacts_patch_id_fkey" FOREIGN KEY ("patch_id") REFERENCES "patches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patch_channels" ADD CONSTRAINT "patch_channels_patch_id_fkey" FOREIGN KEY ("patch_id") REFERENCES "patches"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "patch_channels" ADD CONSTRAINT "patch_channels_channel_id_fkey" FOREIGN KEY ("channel_id") REFERENCES "channels"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "audit_log" ADD CONSTRAINT "audit_log_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "users"("id") ON DELETE SET NULL ON UPDATE CASCADE;
