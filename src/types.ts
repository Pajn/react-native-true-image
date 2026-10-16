import type { ColorValue, ViewProps } from 'react-native';

/** A remote source with request headers, for servers behind a proxy or auth. */
export interface ImageURISource {
  uri: string;
  /** Sent with the request. Not part of the cache key. */
  headers?: Record<string, string>;
  /**
   * Names the picture this URL shows. URLs that share a cache key are the
   * same picture at different resolutions, such as one image proxied at
   * several sizes. A view shows a cached variant that is large enough
   * instead of fetching `uri`, and shows a smaller cached one while `uri`
   * loads. Prefetches register their variant; `getColors` samples a cached
   * variant without fetching.
   */
  cacheKey?: string;
}

/**
 * A remote URL, a `file://` URI, a scheme-less native resource name
 * (asset catalog image on iOS, drawable on Android), a `require()`d
 * asset, or a `{ uri, headers }` object. `null` and `undefined` clear the view.
 */
export type ImageSource = string | number | ImageURISource | null | undefined;

/** View dimensions in React Native layout units. */
export interface DisplaySize {
  width: number;
  height: number;
}

export interface PrefetchOptions {
  /** Expected view size in React Native layout units, before screen density. */
  displaySize?: DisplaySize;
  /** @default 'cover' */
  resizeMode?: ResizeMode;
  /** Same policy as Image.downsampleThreshold. @default 2 */
  downsampleThreshold?: number;
}

/**
 * Colours picked from an image, each as `#rrggbb`. The six named swatches
 * follow Android's Palette targets and are null when no colour in the image
 * fits one; a colour fills one target at most.
 */
export interface ImageColors {
  /**
   * The most common colour. Near black, near white and skin-like reds are
   * filtered first, as in Palette; the mean colour if nothing else is left.
   */
  dominant: string;
  vibrant: string | null;
  lightVibrant: string | null;
  darkVibrant: string | null;
  muted: string | null;
  lightMuted: string | null;
  darkMuted: string | null;
}

export interface ImageColorsOptions {
  /**
   * Sent with the request, like `ImageURISource.headers`. A `{ uri, headers }`
   * source's own headers win over these.
   */
  headers?: Record<string, string>;
}

/** What `Image.prefetch` accepts, with optional per-image decode settings. */
export type PrefetchSource = string | (ImageURISource & PrefetchOptions);

export type ResizeMode = 'cover' | 'contain' | 'stretch' | 'center';

/**
 * Where a remote placeholder may come from. `cache-only` shows it only if it
 * is already in the memory or disk cache; `network` fetches it like any
 * image. Local placeholders (`require()` assets, native resource names,
 * `file://` URIs) always show.
 */
export type PlaceholderPolicy = 'cache-only' | 'network';

export interface ImageLoadEvent {
  /**
   * Decoded width in pixels. For a source with a `cacheKey` this may be a
   * reused variant of the picture, whose size differs from the URL's.
   */
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
  /**
   * Decode oversized bitmaps near their displayed pixel size when the source
   * resolution exceeds it by this linear factor. Defaults to 2. Set 1 to
   * downsample whenever oversized, or 0 to disable. Other values must be >= 1.
   * Does not downsample resizeMode="center" or native vector resources.
   */
  downsampleThreshold?: number;
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
   * When `source` has a `cacheKey` and a smaller variant of it is cached,
   * that variant is preferred over a remote `cache-only` placeholder.
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

/** Default linear oversize factor before decode-time downsampling. */
export const DEFAULT_DOWNSAMPLE_THRESHOLD = 2;
