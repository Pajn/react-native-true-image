import { useMemo, useRef, type Ref } from 'react';
import { Image as RNImage, StyleSheet, type HostInstance } from 'react-native';
import NativeTrueImage from './specs/NativeTrueImage';
import TrueImageView from './specs/TrueImageViewNativeComponent';
import {
  DEFAULT_BLUR_PIXELS_PER_RADIUS,
  DEFAULT_TRANSITION,
  type ImageErrorEvent,
  type ImageLoadEvent,
  type ImageProps,
  type ImageSource,
  type PrefetchSource,
} from './types';

export type ImageRef = HostInstance;

type NativeHeader = { name: string; value: string };

export interface ResolvedSource {
  uri: string | undefined;
  headers: NativeHeader[] | undefined;
}

/**
 * Collapses every accepted `source` into the string the native side
 * understands plus optional headers. Remote and `file://` URLs pass through
 * unchanged; a `require()` asset id becomes whatever the packager resolves it
 * to (a `file://` or `http://` URI in development, a bundled resource name in
 * release builds). Unknown asset ids resolve to `undefined` rather than
 * throwing.
 */
export function resolveSource(source: ImageSource): ResolvedSource {
  if (source == null) return { uri: undefined, headers: undefined };
  if (typeof source === 'string') return { uri: source, headers: undefined };
  if (typeof source === 'number') {
    const resolved = RNImage.resolveAssetSource(source);
    return { uri: resolved?.uri ?? undefined, headers: undefined };
  }
  return { uri: source.uri, headers: toNativeHeaders(source.headers) };
}

function toNativeHeaders(
  headers: Record<string, string> | undefined
): NativeHeader[] | undefined {
  if (headers === undefined) return undefined;
  const list = Object.entries(headers).map(([name, value]) => ({
    name,
    value,
  }));
  return list.length > 0 ? list : undefined;
}

/**
 * Remote images fade in by default; bundled assets are already on disk and
 * draw at once. An explicit `transition` always wins.
 */
export function resolveTransition(
  source: ImageSource,
  transition: number | undefined
): number {
  if (transition !== undefined) return transition;
  return typeof source === 'number' ? 0 : DEFAULT_TRANSITION;
}

function useLatest<T>(value: T) {
  const ref = useRef(value);
  ref.current = value;
  return ref;
}

function ImageComponent({
  source,
  transition,
  resizeMode = 'cover',
  blurRadius = 0,
  blurPixelsPerRadius = DEFAULT_BLUR_PIXELS_PER_RADIUS,
  onLoad,
  onError,
  onDisplay,
  onDisplayEnd,
  style,
  ref,
  ...rest
}: ImageProps & { ref?: Ref<ImageRef> }) {
  const latest = useLatest({ onLoad, onError, onDisplay, onDisplayEnd });
  const resolved = resolveSource(source);

  // Native only gets a handler when the caller supplied one, so the
  // native side can skip emitting events nobody listens to. The wrappers
  // are stable across renders to avoid prop churn on every parent render.
  const hasLoad = onLoad !== undefined;
  const hasError = onError !== undefined;
  const hasDisplay = onDisplay !== undefined;
  const hasDisplayEnd = onDisplayEnd !== undefined;

  const handlers = useMemo(
    () => ({
      onLoad: hasLoad
        ? (e: { nativeEvent: ImageLoadEvent }) =>
            latest.current.onLoad?.(e.nativeEvent)
        : undefined,
      onError: hasError
        ? (e: { nativeEvent: ImageErrorEvent }) =>
            latest.current.onError?.(e.nativeEvent)
        : undefined,
      onDisplay: hasDisplay ? () => latest.current.onDisplay?.() : undefined,
      onDisplayEnd: hasDisplayEnd
        ? () => latest.current.onDisplayEnd?.()
        : undefined,
    }),
    [hasLoad, hasError, hasDisplay, hasDisplayEnd, latest]
  );

  return (
    <TrueImageView
      {...rest}
      ref={ref}
      source={resolved.uri}
      headers={resolved.headers}
      transition={resolveTransition(source, transition)}
      resizeMode={resizeMode}
      blurRadius={blurRadius}
      blurPixelsPerRadius={blurPixelsPerRadius}
      style={[styles.image, style]}
      {...handlers}
    />
  );
}

/**
 * Warms the memory cache with the exact request a mounting `Image` will
 * make, so the view's load is a synchronous memory hit. Resolves `false`
 * if any URL failed.
 */
function prefetch(
  sources: PrefetchSource | readonly PrefetchSource[]
): Promise<boolean> {
  const list = Array.isArray(sources)
    ? (sources as readonly PrefetchSource[])
    : [sources as PrefetchSource];
  return NativeTrueImage.prefetch(
    list.map((item) =>
      typeof item === 'string'
        ? { uri: item }
        : { uri: item.uri, headers: toNativeHeaders(item.headers) }
    )
  );
}

export const Image = Object.assign(ImageComponent, { prefetch });

const styles = StyleSheet.create({
  image: {
    overflow: 'hidden',
  },
});
