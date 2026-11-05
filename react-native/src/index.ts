import NativeOta from './NativeOta';

export type OtaState = {
  /** The release this app reports, such as `1.0+1`. */
  releaseVersion: string;
  /** The patch running now, or null when running the bundle inside the app. */
  bootedPatch: number | null;
  /** The patch confirmed to work. */
  currentPatch: number | null;
  /** A patch downloaded and waiting for the next launch. */
  nextPatch: number | null;
  /** False when `ota.yaml` is missing from the app. */
  configured: boolean;
  appId: string | null;
  channel: string;
  autoUpdate: boolean;
};

export type UpdateCheck = {
  status: 'disabled' | 'up-to-date' | 'downloaded';
  /** The patch that was downloaded. It runs on the next launch. */
  patchNumber?: number;
};

/**
 * How long a new patch must run before it counts as working. A patch that
 * crashes the app before this is removed on the next launch.
 */
const READY_DELAY_MS = 2000;

/** The state of updates on this device. */
export function getState(): Promise<OtaState> {
  return NativeOta.getState() as Promise<OtaState>;
}

/**
 * Checks the server now. A new patch downloads in the background and runs on
 * the next launch.
 */
export function checkForUpdate(): Promise<UpdateCheck> {
  return NativeOta.checkForUpdate() as Promise<UpdateCheck>;
}

/**
 * Confirms the running patch works. Runs by itself shortly after launch; call it
 * sooner only if your app has its own earlier signal.
 */
export function markReady(): void {
  NativeOta.markReady();
}

// `__DEV__` builds load from Metro and never touch updates.
if (!__DEV__) {
  setTimeout(async () => {
    markReady();
    try {
      const state = await getState();
      if (state.autoUpdate) await checkForUpdate();
    } catch (error) {
      // No network is normal on a phone. The next launch tries again.
      console.log(`ota: update check failed: ${String(error)}`);
    }
  }, READY_DELAY_MS);
}
