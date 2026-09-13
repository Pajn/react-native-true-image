import type { ImageProps } from './types';

function ImageComponent(_props: ImageProps): never {
  throw new Error(
    "'react-native-true-image' is only supported on native platforms."
  );
}

function prefetch(_urls: string | readonly string[]): Promise<boolean> {
  return Promise.reject(
    new Error(
      "'react-native-true-image' is only supported on native platforms."
    )
  );
}

export const Image = Object.assign(ImageComponent, { prefetch });

export type ImageRef = never;
