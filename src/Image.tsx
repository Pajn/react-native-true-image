import type {
  ImageColors,
  ImageColorsOptions,
  ImageProps,
  ImageSource,
  PrefetchOptions,
  PrefetchSource,
} from './types';

function ImageComponent(_props: ImageProps): never {
  throw new Error(
    "'react-native-true-image' is only supported on native platforms."
  );
}

function prefetch(
  _sources: PrefetchSource | readonly PrefetchSource[],
  _options?: PrefetchOptions
): Promise<boolean> {
  return Promise.reject(
    new Error(
      "'react-native-true-image' is only supported on native platforms."
    )
  );
}

function getColors(
  _source: ImageSource,
  _options?: ImageColorsOptions
): Promise<ImageColors | null> {
  return Promise.reject(
    new Error(
      "'react-native-true-image' is only supported on native platforms."
    )
  );
}

export const Image = Object.assign(ImageComponent, { prefetch, getColors });

export type ImageRef = never;
