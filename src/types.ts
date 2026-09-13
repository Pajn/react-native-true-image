import type { ColorValue, ViewProps } from 'react-native';

/** A remote source with request headers, for servers behind a proxy or auth. */
export interface ImageURISource {
  uri: string;
  /** Sent with the request. Not part of the cache key. */
  headers?: Record<string, string>;
}

/**
 * A remote URL, a `file://` URI, a scheme-less native resource name
 * (asset catalog image on iOS, drawable on Android), a `require()`d
 * asset, or a `{ uri, headers }` object. `null` and `undefined` clear the view.
 */
export type ImageSource = string | number | ImageURISource | null | undefined;

/** What `Image.prefetch` accepts: the same shapes as `source`, minus assets. */
export type PrefetchSource = string | ImageURISource;

export type ResizeMode = 'cover' | 'contain' | 'stretch' | 'center';

/**
 * Where a remote placeholder may come from. `cache-only` shows it only if it
 * is already in the memory or disk cache; `network` fetches it like any
 * image. Local placeholders (`require()` assets, native resource names,
 * `file://` URIs) always show.
 */
export type PlaceholderPolicy = 'cache-only' | 'network';

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
  /**
   * How much detail a blur keeps. Before blurring, the image is shrunk until
   * `blurRadius` spans this many pixels, and the blur runs on the small
   * copy: a blur erases everything finer than its radius, so the result
   * looks the same and a large blur of a large image costs a fraction as
   * much. Higher keeps more pixels and costs more; `0` blurs at full size.
   * Defaults to `DEFAULT_BLUR_PIXELS_PER_RADIUS`.
   */
  blurPixelsPerRadius?: number;
  /** Applied to native resource images only; remote bitmaps are never tinted. */
  tintColor?: ColorValue;
  /**
   * Shown into an empty view until `source` loads, then crossfaded out over
   * `placeholderTransition`. Accepts the same shapes as `source`. It appears
   * only while the view is empty: on mount, after a `recyclingKey` change, or
   * after `source` was cleared. A displayed image is never replaced by a
   * placeholder while its successor loads. It draws at once, never fades in,
   * and reports no events; `onLoad` and friends describe `source` alone.
   */
  placeholder?: ImageSource;
  /**
   * Crossfade from the placeholder to the image, in milliseconds. Defaults
   * to the resolved `transition`; `0` cuts.
   */
  placeholderTransition?: number;
  /** @default 'cache-only' */
  placeholderPolicy?: PlaceholderPolicy;
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

/**
 * Pixels the blur radius spans after the pre-blur shrink when
 * `blurPixelsPerRadius` is omitted. Two is under a pixel of error in the
 * blurred result.
 */
export const DEFAULT_BLUR_PIXELS_PER_RADIUS = 2;
