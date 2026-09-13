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

export interface NativeProps extends ViewProps {
  /**
   * Remote URL, `file://` URI, or a scheme-less native resource name
   * (asset catalog image on iOS, drawable on Android).
   */
  source?: string;
  resizeMode?: CodegenTypes.WithDefault<
    'cover' | 'contain' | 'stretch' | 'center',
    'cover'
  >;
  /** Fade duration in milliseconds. 0 disables fading. */
  transition?: CodegenTypes.WithDefault<CodegenTypes.Int32, 0>;
  /** Gaussian blur radius in source-image pixels. */
  blurRadius?: CodegenTypes.WithDefault<CodegenTypes.Float, 0>;
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
