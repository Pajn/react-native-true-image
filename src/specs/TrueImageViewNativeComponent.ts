import {
  codegenNativeComponent,
  type CodegenTypes,
  type ColorValue,
  type HostComponent,
  type ViewProps,
} from 'react-native';

type LoadEvent = Readonly<{
  /** Decoded width in pixels. */
  width: CodegenTypes.Float;
  /** Decoded height in pixels. */
  height: CodegenTypes.Float;
  /** The `source` string the image was loaded for. */
  source: string;
}>;

type ErrorEvent = Readonly<{
  error: string;
  source: string;
}>;

type Header = Readonly<{
  name: string;
  value: string;
}>;

export interface NativeProps extends ViewProps {
  /**
   * Remote URL, `file://` URI, or a scheme-less native resource name
   * (asset catalog image on iOS, drawable on Android).
   */
  source?: string;
  /** Request headers for remote sources. Not part of the cache key. */
  headers?: ReadonlyArray<Header>;
  resizeMode?: CodegenTypes.WithDefault<
    'cover' | 'contain' | 'stretch' | 'center',
    'cover'
  >;
  /** Fade duration in milliseconds. 0 disables fading. */
  transition?: CodegenTypes.WithDefault<CodegenTypes.Int32, 0>;
  /** Gaussian blur radius in source-image pixels. */
  blurRadius?: CodegenTypes.WithDefault<CodegenTypes.Float, 0>;
  /**
   * Pixels the blur radius spans after the image is shrunk for blurring.
   * 0 blurs at full size.
   */
  blurPixelsPerRadius?: CodegenTypes.WithDefault<CodegenTypes.Float, 2>;
  tintColor?: ColorValue;
  recyclingKey?: string;

  onLoad?: CodegenTypes.DirectEventHandler<LoadEvent>;
  onError?: CodegenTypes.DirectEventHandler<ErrorEvent>;
  onDisplay?: CodegenTypes.DirectEventHandler<null>;
  onDisplayEnd?: CodegenTypes.DirectEventHandler<null>;
}

export default codegenNativeComponent<NativeProps>(
  'TrueImageView'
) as HostComponent<NativeProps>;
