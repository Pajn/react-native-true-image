import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type NativePrefetchRequest = Readonly<{
  uri: string;
  displayWidth?: number;
  displayHeight?: number;
  resizeMode?: string;
  downsampleThreshold?: number;
  headers?: ReadonlyArray<Readonly<{ name: string; value: string }>>;
}>;

export interface Spec extends TurboModule {
  /**
   * Loads every URL into memory. Matching dimensions and decode settings
   * give a mounting view a synchronous memory hit.
   * Resolves `true` only if every URL succeeded.
   */
  prefetch(requests: ReadonlyArray<NativePrefetchRequest>): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TrueImage');
