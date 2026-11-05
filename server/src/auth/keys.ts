import * as crypto from 'crypto';

/** CLI API keys: `ota_` followed by 48 hex characters. Stored as sha256. */
export const API_KEY_PREFIX = 'ota_';
export const generateApiKey = () => API_KEY_PREFIX + crypto.randomBytes(24).toString('hex');
export const hashApiKey = (key: string) => crypto.createHash('sha256').update(key).digest('hex');
export const keyPrefixForDisplay = (key: string) => key.slice(0, API_KEY_PREFIX.length + 6);

/** Password hashing with Node's built-in scrypt (no native dependency). */
export function hashPassword(password: string): string {
  const salt = crypto.randomBytes(16).toString('hex');
  const hash = crypto.scryptSync(password, salt, 64).toString('hex');
  return `scrypt$${salt}$${hash}`;
}
export function verifyPassword(password: string, stored: string): boolean {
  const [algo, salt, hash] = stored.split('$');
  if (algo !== 'scrypt' || !salt || !hash) return false;
  const candidate = crypto.scryptSync(password, salt, 64);
  const expected = Buffer.from(hash, 'hex');
  return candidate.length === expected.length && crypto.timingSafeEqual(candidate, expected);
}
