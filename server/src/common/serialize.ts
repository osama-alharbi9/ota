/** JSON helpers for the CLI protocol wire shapes. */
export const iso = (d: Date) => d.toISOString();
export const num = (b: bigint | number) => Number(b);
export const jsonSafe = <T>(v: T): T => JSON.parse(JSON.stringify(v, (_k, x) => (typeof x === 'bigint' ? Number(x) : x)));
