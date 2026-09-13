import { TurboModuleRegistry, type TurboModule } from 'react-native';

export interface Spec extends TurboModule {
  /**
   * Loads every URL into the memory cache using the exact request the view
   * uses, so a view mounting later gets a synchronous memory hit.
   * Resolves `true` only if every URL succeeded.
   */
  prefetch(urls: string[]): Promise<boolean>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TrueImage');
