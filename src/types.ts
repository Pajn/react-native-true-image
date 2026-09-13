import type { ColorValue, ViewProps } from 'react-native';

/**
 * A remote URL, a `file://` URI, a scheme-less native resource name
 * (asset catalog image on iOS, drawable on Android), or a `require()`d
 * asset. `null` and `undefined` clear the view.
 */
export type ImageSource = string | number | null | undefined;

export type ResizeMode = 'cover' | 'contain' | 'stretch' | 'center';

export interface ImageLoadEvent {
  /** Decoded width in pixels. */
  width: number;
  /** Decoded height in pixels. */
  height: number;
  /** The resolved `source` string the image was loaded for. */
  source: string;
}

export interface ImageErrorEvent {
  error: string;
  source: string;
}

export interface ImageProps extends ViewProps {
  source?: ImageSource;
  /** @default 'cover' */
  resizeMode?: ResizeMode;
  /**
   * Fade-in duration in milliseconds. Defaults to `DEFAULT_TRANSITION` for
   * URL sources and `0` for `require()`d assets. Native resource names never
   * fade regardless of this value. A memory-cached image arriving into an
   * empty view also draws at once; replacing a displayed image always
   * crossfades.
   */
  transition?: number;
  /** Gaussian blur radius in source-image pixels. */
  blurRadius?: number;
  /** Applied to native resource images only; remote bitmaps are never tinted. */
  tintColor?: ColorValue;
  /**
   * Changing this clears the view synchronously before the next source loads.
   * Set it to the row's item id in recycled lists so a reused row never
   * crossfades the previous item's image into the new one.
   */
  recyclingKey?: string;
  /** The image decoded. Fires before it is drawn. */
  onLoad?: (event: ImageLoadEvent) => void;
  /** The load failed. Not fired for loads cancelled by a newer source. */
  onError?: (event: ImageErrorEvent) => void;
  /** The image was handed to the view: at the start of a fade, or on draw. */
  onDisplay?: () => void;
  /**
   * The image is fully drawn: after the fade, or together with `onDisplay`
   * when there is none. An image whose fade is interrupted never reports
   * this; the newer image reports in its turn.
   */
  onDisplayEnd?: () => void;
}

/** Fade duration in milliseconds applied to URL sources when `transition` is omitted. */
export const DEFAULT_TRANSITION = 300;
