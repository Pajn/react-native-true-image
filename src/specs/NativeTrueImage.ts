import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type NativePrefetchRequest = Readonly<{
  uri: string;
  headers?: ReadonlyArray<Readonly<{ name: string; value: string }>>;
}>;

export interface Spec extends TurboModule {
  /**
   * Loads every URL into the memory cache using the exact request the view
   * uses, so a view mounting later gets a synchronous memory hit.
   * Resolves `true` only if every URL succeeded.
   */
  prefetch(requests: ReadonlyArray<NativePrefetchRequest>): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TrueImage');
