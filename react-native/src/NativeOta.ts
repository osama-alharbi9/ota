import { TurboModuleRegistry, type TurboModule } from 'react-native';

export interface Spec extends TurboModule {
  getState(): Promise<Object>;
  checkForUpdate(): Promise<Object>;
  markReady(): void;
}

export default TurboModuleRegistry.getEnforcing<Spec>('Ota');
