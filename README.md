# react-native-true-image

A single-layer image component for React Native with a cache-key contract
between `prefetch` and the view, so a prefetched image mounts as a
synchronous memory hit. Built as a Fabric component and TurboModule on
SDWebImage (iOS) and Glide (Android).

One native view draws one image on one layer (iOS) or one canvas (Android).
No subviews, no placeholder views.

## Installation

```sh
yarn add react-native-true-image
```

Requires React Native 0.76 or later with the new architecture enabled.
Expo apps need a development build; the package works with `expo prebuild`
without a config plugin.

## Usage

```tsx
import { Image } from 'react-native-true-image';

<Image
  source="https://cdn.example.com/cover.jpg"
  recyclingKey={item.id}
  transition={300}
  style={{ width: 120, height: 120, borderRadius: 8 }}
  onDisplayEnd={() => setFallbackVisible(false)}
/>;

await Image.prefetch(covers.map((c) => c.url));
```

### Sources

| Input | What native receives | Path |
| --- | --- | --- |
| Remote URL | the string as-is | SDWebImage / Glide through OkHttp |
| `require()` asset | `Image.resolveAssetSource().uri` | file loader / drawable |
| Scheme-less name, e.g. `"ic_play"` | the bare name | iOS asset catalog / Android drawable |

Scheme-less names are drawn in the same frame and never fade, which makes
them suitable for icons. `tintColor` applies to them only.

### Props

| Prop | Default | Notes |
| --- | --- | --- |
| `source` | | `string`, `require()` id, or `null` to clear |
| `resizeMode` | `'cover'` | `cover`, `contain`, `stretch`, `center` |
| `transition` | 300 ms for URLs, 0 for assets | Fade duration in milliseconds |
| `blurRadius` | 0 | In source-image pixels, so the same value looks the same on both platforms |
| `tintColor` | | Native resources only |
| `recyclingKey` | | Clears the view synchronously when it changes, before the next source loads |

### Events

- `onLoad({ width, height, source })`: the image decoded. Sizes are pixels.
- `onError({ error, source })`: the load failed. Not fired for a load cancelled by a newer source.
- `onDisplay()`: the image was handed to the view, at the start of a fade or on draw.
- `onDisplayEnd()`: the image is fully drawn, after the fade or together with `onDisplay` when there is none.

A fade softens an image arriving late. A memory-cached image arriving into an
empty view draws at once regardless of `transition`. Replacing a displayed
image always crossfades. An image whose fade is interrupted never reports
`onDisplayEnd`; the newer image reports in its turn.

### Prefetch

`Image.prefetch(url | url[])` resolves `true` only if every URL loaded. Both
the prefetch and the view build the identical request, so a view that mounts
after a prefetch gets the image synchronously from memory. This is the
module's central contract; anything that adds view size to the request key
breaks it.

## Android: parallel decoding of disk-cached images

Glide decodes disk-cached images on a single thread by default. Fresh
downloads decode on a pool of up to four threads, but a `DecodeJob` for an
image already on disk runs on the disk cache executor, which has one thread.
A cold scroll through a list whose images are on disk decodes them one at a
time.

Executors can only be configured through the app's `AppGlideModule`, so this
package cannot change it on its own. To opt in, add the Glide annotation
processor to your app and call the helper from `applyOptions`:

```kotlin
import com.bumptech.glide.GlideBuilder
import com.bumptech.glide.annotation.GlideModule
import com.bumptech.glide.module.AppGlideModule
import com.trueimage.TrueImageGlideOptions

@GlideModule
class AppGlide : AppGlideModule() {
  override fun applyOptions(context: Context, builder: GlideBuilder) {
    TrueImageGlideOptions.apply(builder)
  }
}
```

`apply` sizes the disk cache executor like Glide's source executor,
`min(4, CPU cores)`. Pass a `threadCount` to choose differently. Prefetched
images are not affected either way, since their decode already happened off
the critical path.

## Development

```sh
yarn            # install
yarn test       # JS contract tests
swift test      # iOS geometry and policy tests, runs on the host
yarn example android
yarn example ios
```

Android policy tests run with the example's Gradle wrapper:

```sh
cd example/android && ./gradlew :react-native-true-image:testDebugUnitTest
```

A Nix flake provides the Android toolchain: `nix develop` for the SDK and
JDK, `nix develop .#emulator` to include an emulator image.

## License

MIT
