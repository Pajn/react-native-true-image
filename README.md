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
| `{ uri, headers }` | the URI plus a header list | same, with the headers on the request |
| `require()` asset | `Image.resolveAssetSource().uri` | file loader / drawable |
| Scheme-less name, e.g. `"ic_play"` | the bare name | iOS asset catalog / Android drawable |

Scheme-less names are drawn in the same frame and never fade, which makes
them suitable for icons. `tintColor` applies to them only.

Headers are sent with the request and are not part of the cache key: the
same URL is one cached image whatever headers fetched it, so a prefetch
with headers and a view without them still share one entry. Pass the same
`{ uri, headers }` object to both when the server needs them.

### Borders and rounded corners

The view takes every `borderRadius`, `borderWidth`, `borderColor` and
`borderStyle` prop a `View` takes, on both platforms, and clips the image
to the border box. There is no need for a clipping wrapper.

```tsx
<Image source={url} style={{ width: 96, height: 96, borderRadius: 12 }} />
```

Clipping relies on the default `overflow: 'hidden'`; overriding it to
`visible` on iOS draws the image square.

### Props

| Prop | Default | Notes |
| --- | --- | --- |
| `source` | | `string`, `{ uri, headers }`, `require()` id, or `null` to clear |
| `resizeMode` | `'cover'` | `cover`, `contain`, `stretch`, `center` |
| `transition` | 300 ms for URLs, 0 for assets | Fade duration in milliseconds |
| `blurRadius` | 0 | In source-image pixels, so the same value looks the same on both platforms |
| `blurPixelsPerRadius` | 2 | Pixels the blur radius spans after the pre-blur shrink; `0` blurs at full size. See [Blur cost](#blur-cost) |
| `tintColor` | | Native resources only |
| `recyclingKey` | | Clears the view synchronously when it changes, before the next source loads |
| `placeholder` | | Shown into an empty view until `source` loads. Same shapes as `source`. See [Placeholder](#placeholder) |
| `placeholderTransition` | same as `transition` | Crossfade from the placeholder to the image, in milliseconds; `0` cuts |
| `placeholderPolicy` | `'cache-only'` | `cache-only` shows a remote placeholder only if already cached; `network` fetches it |

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

`Image.prefetch(source | source[])` takes URL strings or `{ uri, headers }`
objects and resolves `true` only if every one loaded. Both the prefetch and
the view build the identical request, so a view that mounts after a prefetch
gets the image synchronously from memory. This is the module's central
contract; anything that adds view size to the request key breaks it.

On Android the prefetch loop runs on a background thread: each load is
started with `submit()` and awaited there, and the main looper sees a single
post per batch. Prefetches usually race the mount work they feed, so they
stay out of its queue.

### Placeholder

A placeholder stands in while `source` loads: a low-resolution copy that a
list row already cached, or a bundled asset. It shows only into an empty
view, which is on mount, after a `recyclingKey` change, or after `source`
was cleared. A displayed image is never swapped for a placeholder while its
replacement loads. The placeholder draws the moment it is available, never
fades in, and reports no events, so `onLoad` and friends always describe
`source`. When the image arrives it crossfades over `placeholderTransition`
or cuts at `0`. An image that is a memory hit shows at once and the
placeholder is never loaded.

`placeholderPolicy` decides where a remote placeholder may come from.
`cache-only` reads the memory and disk caches and gives up silently
otherwise, so it never costs a request. `network` fetches it like any other
image, through the same request as a view or prefetch of that URL, so it
lands in the shared cache. Local placeholders always show. `blurRadius` and
`resizeMode` apply to the placeholder as well.

## Blur cost

A Gaussian blur erases every detail finer than its radius, so blurring a
copy shrunk until the radius spans a couple of pixels looks the same as
blurring the original. `blurPixelsPerRadius` sets how many pixels that is.
With the default of 2, a radius of 100 shrinks the image fifty times per
axis and blurs it with a radius of 2. Raise it to keep more detail in the
blurred image, or set it to `0` to blur at full size.

Both platforms blur once, off the main thread, and then draw the blurred
bitmap like any other. A crossfade between blurred images is two bitmap
draws per frame, with no per-frame filter: a blur is linear, so fading
between two blurred images is pixel-identical to blurring the fade. A
blurred image is never shown sharp first; it appears once the blur is done.

On iOS the shrink runs inside the SDWebImage transform and the result is
cached under a key that includes the shrink factor. The sharp original stays
cached and is the transform input, so a blurred view still reuses a
prefetch. On Android the view blurs the drawable Glide hands it, so the
request and its memory cache entry stay identical to the prefetch, and a
small cache keyed on source, radius and factor makes the blur a synchronous
hit for recycled rows. The two blurs use the same three-pass box
approximation of a Gaussian, so one radius looks the same on both.

## Android: parallel decoding of disk-cached images

Glide decodes disk-cached images on a single thread by default. Fresh
downloads decode on a pool of up to four threads, but a `DecodeJob` for an
image already on disk runs on the disk cache executor, which has one thread.
A cold scroll through a list whose images are on disk decodes them one at a
time.

Measure before opting in. On one launch profile with twenty prefetched
covers, decode was under a third of the batch's wall time and adding threads
changed time-to-paint by under one percent; the rest was main-thread
scheduling, which the background prefetch loop now avoids. The helper helps
a cold scroll of disk-cached images that were not prefetched, and little
else.

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
`min(4, CPU cores)`. Pass a `threadCount` to choose differently.

## Development

```sh
yarn            # install
yarn test       # JS contract tests
swift test      # iOS geometry and policy tests, runs on the host
yarn example android
yarn example ios
```

Android unit tests (pure policy plus Robolectric tests of the view and the
prefetch contract against Glide) run with the example's Gradle wrapper:

```sh
cd example/android && ./gradlew :react-native-true-image:testDebugUnitTest
```

iOS view and prefetch tests run as an XCTest bundle hosted by the example
app, against SDWebImage with a fake network:

```sh
cd example/ios && xcodebuild test -workspace TrueImageExample.xcworkspace \
  -scheme TrueImageExample -destination 'platform=iOS Simulator,name=iPhone 15 Pro'
```

A Nix flake provides the Android toolchain: `nix develop` for the SDK and
JDK, `nix develop .#emulator` to include an emulator image.

## License

MIT
