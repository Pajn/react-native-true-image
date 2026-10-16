import { TurboModuleRegistry, type TurboModule } from 'react-native';

export type NativePrefetchRequest = Readonly<{
  uri: string;
  displayWidth?: number;
  displayHeight?: number;
  resizeMode?: string;
  downsampleThreshold?: number;
  headers?: ReadonlyArray<Readonly<{ name: string; value: string }>>;
  /** Registers the loaded image as a variant of the picture this key names. */
  cacheKey?: string;
}>;

export interface Spec extends TurboModule {
  /**
   * Loads every URL into memory. Matching dimensions and decode settings
   * give a mounting view a synchronous memory hit.
   * Resolves `true` only if every URL succeeded.
   */
  prefetch(requests: ReadonlyArray<NativePrefetchRequest>): Promise<boolean>;
  /**
   * Decodes the image through the same pipeline and cache as a view, scales
   * it to `size` × `size` and resolves its pixels as base64: 8-bit RGBA, not
   * premultiplied, row-major. Resolves null if it could not be loaded or
   * decoded, or if `size` is not between 1 and 256. With a `cacheKey`, a
   * cached variant of the picture is sampled instead of fetching `uri`.
   */
  getPixels(
    uri: string,
    size: number,
    headers?: ReadonlyArray<Readonly<{ name: string; value: string }>>,
    cacheKey?: string
  ): Promise<string | null>;
}

export default TurboModuleRegistry.getEnforcing<Spec>('TrueImage');
