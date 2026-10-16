import { beforeEach, describe, expect, it, jest } from '@jest/globals';
import { render, screen } from '@testing-library/react-native';
import { Image as RNImage } from 'react-native';
import {
  COLOR_SAMPLE_SIZE,
  Image,
  resolveSource,
  resolveTransition,
} from '../Image.native';
import { DEFAULT_TRANSITION } from '../types';

const mockPrefetch = jest.fn<(requests: unknown[]) => Promise<boolean>>();
const mockGetPixels =
  jest.fn<
    (
      uri: string,
      size: number,
      headers: unknown,
      cacheKey: unknown
    ) => Promise<string | null>
  >();

jest.mock('../specs/NativeTrueImage', () => ({
  __esModule: true,
  default: {
    prefetch: (requests: unknown[]) => mockPrefetch(requests),
    getPixels: (
      uri: string,
      size: number,
      headers: unknown,
      cacheKey: unknown
    ) => mockGetPixels(uri, size, headers, cacheKey),
  },
}));

jest.mock('../specs/TrueImageViewNativeComponent', () => {
  const React = require('react');
  const { View } = require('react-native');
  return {
    __esModule: true,
    default: (props: object) =>
      React.createElement(View, { testID: 'native', ...props }),
  };
});

function nativeProps() {
  return screen.getByTestId('native').props as Record<string, unknown>;
}

beforeEach(() => {
  mockPrefetch.mockReset();
  mockPrefetch.mockResolvedValue(true);
  mockGetPixels.mockReset();
  mockGetPixels.mockResolvedValue(null);
});

describe('source resolution', () => {
  it('passes null through as undefined', async () => {
    await render(<Image source={null} />);
    expect(nativeProps().source).toBeUndefined();
    expect(nativeProps().headers).toBeUndefined();
    expect(resolveSource(undefined).uri).toBeUndefined();
  });

  it('passes a URL string through unchanged', async () => {
    const url = 'https://cdn.example.com/cover.jpg?w=300';
    await render(<Image source={url} />);
    expect(nativeProps().source).toBe(url);
  });

  it('resolves a require() asset through Image.resolveAssetSource', async () => {
    const spy = jest
      .spyOn(RNImage, 'resolveAssetSource')
      .mockReturnValue({ uri: 'file:///bundle/cover.png' } as never);
    await render(<Image source={42} />);
    expect(spy).toHaveBeenCalledWith(42);
    expect(nativeProps().source).toBe('file:///bundle/cover.png');
    spy.mockRestore();
  });

  it('resolves an unknown asset id to undefined without throwing', async () => {
    expect(resolveSource(999_999).uri).toBeUndefined();
  });

  it('splits a { uri, headers } source into uri and a header list', async () => {
    await render(
      <Image
        source={{
          uri: 'https://x/a.jpg',
          headers: { 'Authorization': 'Bearer t', 'X-Proxy': 'shelf' },
        }}
      />
    );
    expect(nativeProps().source).toBe('https://x/a.jpg');
    expect(nativeProps().headers).toEqual([
      { name: 'Authorization', value: 'Bearer t' },
      { name: 'X-Proxy', value: 'shelf' },
    ]);
  });

  it('sends no header list for a uri object without headers', async () => {
    await render(<Image source={{ uri: 'https://x/a.jpg', headers: {} }} />);
    expect(nativeProps().headers).toBeUndefined();
  });

  it('passes a cacheKey through and leaves it undefined otherwise', async () => {
    await render(
      <Image
        source={{ uri: 'https://x/a.jpg?size=512', cacheKey: 'album-1' }}
      />
    );
    expect(nativeProps().source).toBe('https://x/a.jpg?size=512');
    expect(nativeProps().cacheKey).toBe('album-1');
    expect(resolveSource('https://x/a.jpg').cacheKey).toBeUndefined();
    expect(resolveSource({ uri: 'https://x/a.jpg' }).cacheKey).toBeUndefined();
    expect(
      resolveSource({ uri: 'https://x/a.jpg', cacheKey: '' }).cacheKey
    ).toBeUndefined();
  });

  it('passes scheme-less resource names through as-is', async () => {
    await render(<Image source="ic_play" />);
    expect(nativeProps().source).toBe('ic_play');
  });
});

describe('transition defaults', () => {
  it('defaults URL sources to DEFAULT_TRANSITION', async () => {
    await render(<Image source="https://example.com/a.jpg" />);
    expect(nativeProps().transition).toBe(DEFAULT_TRANSITION);
  });

  it('defaults bundled assets to 0', async () => {
    expect(resolveTransition(42, undefined)).toBe(0);
  });

  it('treats a uri object like a URL string', async () => {
    expect(resolveTransition({ uri: 'https://x/a.jpg' }, undefined)).toBe(
      DEFAULT_TRANSITION
    );
  });

  it('does not overwrite an explicit transition of 0 on a URL', async () => {
    await render(<Image source="https://example.com/a.jpg" transition={0} />);
    expect(nativeProps().transition).toBe(0);
  });

  it('respects an explicit transition on a bundled asset', async () => {
    expect(resolveTransition(42, 250)).toBe(250);
  });
});

describe('events', () => {
  it('unwraps nativeEvent for onLoad and onError', async () => {
    const onLoad = jest.fn();
    const onError = jest.fn();
    await render(
      <Image source="https://x/a.jpg" onLoad={onLoad} onError={onError} />
    );
    const props = nativeProps() as {
      onLoad: (e: unknown) => void;
      onError: (e: unknown) => void;
    };
    const load = { width: 600, height: 600, source: 'https://x/a.jpg' };
    const error = { error: 'HTTP 404', source: 'https://x/a.jpg' };
    props.onLoad({ nativeEvent: load });
    props.onError({ nativeEvent: error });
    expect(onLoad).toHaveBeenCalledWith(load);
    expect(onError).toHaveBeenCalledWith(error);
  });

  it('calls onDisplay and onDisplayEnd with no arguments', async () => {
    const onDisplay = jest.fn();
    const onDisplayEnd = jest.fn();
    await render(
      <Image
        source="https://x/a.jpg"
        onDisplay={onDisplay}
        onDisplayEnd={onDisplayEnd}
      />
    );
    const props = nativeProps() as {
      onDisplay: (e: unknown) => void;
      onDisplayEnd: (e: unknown) => void;
    };
    props.onDisplay({ nativeEvent: {} });
    props.onDisplayEnd({ nativeEvent: {} });
    expect(onDisplay).toHaveBeenCalledWith();
    expect(onDisplayEnd).toHaveBeenCalledWith();
  });

  it('leaves handlers undefined when not supplied', async () => {
    await render(<Image source="https://x/a.jpg" />);
    const props = nativeProps();
    expect(props.onLoad).toBeUndefined();
    expect(props.onError).toBeUndefined();
    expect(props.onDisplay).toBeUndefined();
    expect(props.onDisplayEnd).toBeUndefined();
  });

  it('keeps handler identity stable across re-renders and calls the latest callback', async () => {
    const first = jest.fn();
    const second = jest.fn();
    const { rerender } = await render(
      <Image source="https://x/a.jpg" onDisplay={first} />
    );
    const before = nativeProps().onDisplay;
    await rerender(<Image source="https://x/a.jpg" onDisplay={second} />);
    const after = nativeProps().onDisplay as () => void;
    expect(after).toBe(before);
    after();
    expect(first).not.toHaveBeenCalled();
    expect(second).toHaveBeenCalledTimes(1);
  });
});

describe('props', () => {
  it('leaves tintColor undefined when not supplied', async () => {
    await render(<Image source="ic_play" />);
    expect(nativeProps().tintColor).toBeUndefined();
  });

  it('passes tintColor and recyclingKey through', async () => {
    await render(
      <Image source="ic_play" tintColor="#ff0000" recyclingKey="row-1" />
    );
    expect(nativeProps().tintColor).toBe('#ff0000');
    expect(nativeProps().recyclingKey).toBe('row-1');
  });

  it('defaults downsampleThreshold to 2 and supports opting out', async () => {
    await render(<Image source="https://x/a.jpg" />);
    expect(nativeProps().downsampleThreshold).toBe(2);
    await render(<Image source="https://x/a.jpg" downsampleThreshold={0} />);
    expect(nativeProps().downsampleThreshold).toBe(0);
  });

  it('defaults resizeMode to cover and blurRadius to 0', async () => {
    await render(<Image source="https://x/a.jpg" />);
    expect(nativeProps().resizeMode).toBe('cover');
    expect(nativeProps().blurRadius).toBe(0);
  });

  it('resolves the placeholder like a source and defaults its options', async () => {
    await render(
      <Image
        source="https://x/a.jpg"
        placeholder={{ uri: 'https://x/a-thumb.jpg', headers: { A: '1' } }}
      />
    );
    expect(nativeProps().placeholder).toBe('https://x/a-thumb.jpg');
    expect(nativeProps().placeholderHeaders).toEqual([
      { name: 'A', value: '1' },
    ]);
    expect(nativeProps().placeholderTransition).toBe(DEFAULT_TRANSITION);
    expect(nativeProps().placeholderFromNetwork).toBe(false);
  });

  it('passes explicit placeholder options through', async () => {
    await render(
      <Image
        source="https://x/a.jpg"
        placeholder="https://x/a-thumb.jpg"
        placeholderTransition={0}
        placeholderPolicy="network"
      />
    );
    expect(nativeProps().placeholderTransition).toBe(0);
    expect(nativeProps().placeholderFromNetwork).toBe(true);
    await render(<Image source="https://x/a.jpg" />);
    expect(nativeProps().placeholder).toBeUndefined();
  });

  it('defaults blurPixelsPerRadius to 2 and passes an override through', async () => {
    await render(<Image source="https://x/a.jpg" />);
    expect(nativeProps().blurPixelsPerRadius).toBe(2);
    await render(<Image source="https://x/a.jpg" blurPixelsPerRadius={0} />);
    expect(nativeProps().blurPixelsPerRadius).toBe(0);
  });

  it('puts overflow hidden before the caller style so callers can override', async () => {
    await render(
      <Image source="https://x/a.jpg" style={{ overflow: 'visible' }} />
    );
    const style = nativeProps().style as unknown[];
    expect(style[0]).toEqual({ overflow: 'hidden' });
    expect(style[1]).toEqual({ overflow: 'visible' });
  });
});

describe('prefetch', () => {
  it('supports batch sizing and per-source overrides', async () => {
    await Image.prefetch(
      [
        'https://x/a.jpg',
        {
          uri: 'https://x/b.jpg',
          displaySize: { width: 40, height: 60 },
          downsampleThreshold: 1,
          resizeMode: 'contain',
        },
      ],
      { displaySize: { width: 100, height: 100 }, downsampleThreshold: 2 }
    );
    expect(mockPrefetch).toHaveBeenCalledWith([
      expect.objectContaining({
        uri: 'https://x/a.jpg',
        displayWidth: 100,
        displayHeight: 100,
        downsampleThreshold: 2,
      }),
      expect.objectContaining({
        uri: 'https://x/b.jpg',
        displayWidth: 40,
        displayHeight: 60,
        downsampleThreshold: 1,
        resizeMode: 'contain',
      }),
    ]);
  });

  it('rejects invalid sizes and thresholds before reaching native code', async () => {
    await expect(
      Image.prefetch('https://x/a.jpg', {
        displaySize: { width: 0, height: 100 },
      })
    ).rejects.toThrow(RangeError);
    for (const downsampleThreshold of [-1, 0.5, NaN, Infinity]) {
      await expect(
        Image.prefetch('https://x/a.jpg', { downsampleThreshold })
      ).rejects.toThrow(RangeError);
    }
    expect(mockPrefetch).not.toHaveBeenCalled();
  });

  it('wraps a single URL in a request list', async () => {
    await expect(Image.prefetch('https://x/a.jpg')).resolves.toBe(true);
    expect(mockPrefetch).toHaveBeenCalledWith([{ uri: 'https://x/a.jpg' }]);
  });

  it('maps an array of URLs to requests', async () => {
    await Image.prefetch(['https://x/a.jpg', 'https://x/b.jpg']);
    expect(mockPrefetch).toHaveBeenCalledWith([
      { uri: 'https://x/a.jpg' },
      { uri: 'https://x/b.jpg' },
    ]);
  });

  it('carries headers into the request, using the same shape as the view', async () => {
    await Image.prefetch([
      { uri: 'https://x/a.jpg', headers: { Authorization: 'Bearer t' } },
      { uri: 'https://x/b.jpg' },
    ]);
    expect(mockPrefetch).toHaveBeenCalledWith([
      {
        uri: 'https://x/a.jpg',
        headers: [{ name: 'Authorization', value: 'Bearer t' }],
      },
      { uri: 'https://x/b.jpg', headers: undefined },
    ]);
  });

  it('carries a cacheKey into the request', async () => {
    await Image.prefetch([
      { uri: 'https://x/a.jpg?size=256', cacheKey: 'album-1' },
      'https://x/b.jpg',
    ]);
    expect(mockPrefetch).toHaveBeenCalledWith([
      expect.objectContaining({
        uri: 'https://x/a.jpg?size=256',
        cacheKey: 'album-1',
      }),
      { uri: 'https://x/b.jpg' },
    ]);
  });

  it('propagates a false result', async () => {
    mockPrefetch.mockResolvedValue(false);
    await expect(Image.prefetch(['https://x/missing.jpg'])).resolves.toBe(
      false
    );
  });
});

describe('getColors', () => {
  /** A sample of one opaque colour, encoded as native sends it. */
  function solid(r: number, g: number, b: number): string {
    const bytes = Buffer.alloc(COLOR_SAMPLE_SIZE * COLOR_SAMPLE_SIZE * 4);
    for (let i = 0; i < bytes.length; i += 4) {
      bytes[i] = r;
      bytes[i + 1] = g;
      bytes[i + 2] = b;
      bytes[i + 3] = 255;
    }
    return bytes.toString('base64');
  }

  it('asks native for a square sample of the URL', async () => {
    mockGetPixels.mockResolvedValue(solid(30, 90, 200));
    const colors = await Image.getColors('https://x/a.jpg');
    expect(mockGetPixels).toHaveBeenCalledWith(
      'https://x/a.jpg',
      COLOR_SAMPLE_SIZE,
      undefined,
      undefined
    );
    expect(colors).toEqual(
      expect.objectContaining({ dominant: '#1e5ac8', vibrant: '#1e5ac8' })
    );
  });

  it('sends option headers, with the source headers winning', async () => {
    await Image.getColors(
      { uri: 'https://x/a.jpg', headers: { Authorization: 'Bearer s' } },
      { headers: { 'Authorization': 'Bearer o', 'X-Proxy': 'shelf' } }
    );
    expect(mockGetPixels).toHaveBeenCalledWith(
      'https://x/a.jpg',
      COLOR_SAMPLE_SIZE,
      [
        { name: 'Authorization', value: 'Bearer s' },
        { name: 'X-Proxy', value: 'shelf' },
      ],
      undefined
    );
  });

  it('resolves a require() asset like the view', async () => {
    const spy = jest
      .spyOn(RNImage, 'resolveAssetSource')
      .mockReturnValue({ uri: 'file:///bundle/cover.png' } as never);
    await Image.getColors(42);
    expect(mockGetPixels).toHaveBeenCalledWith(
      'file:///bundle/cover.png',
      COLOR_SAMPLE_SIZE,
      undefined,
      undefined
    );
    spy.mockRestore();
  });

  it('sends the source cacheKey so native can sample a cached variant', async () => {
    await Image.getColors({
      uri: 'https://x/a.jpg?size=80',
      cacheKey: 'album-1',
    });
    expect(mockGetPixels).toHaveBeenCalledWith(
      'https://x/a.jpg?size=80',
      COLOR_SAMPLE_SIZE,
      undefined,
      'album-1'
    );
  });

  it('resolves null when native could not load the image', async () => {
    await expect(Image.getColors('https://x/missing.jpg')).resolves.toBeNull();
  });

  it('resolves null for a sample of the wrong size', async () => {
    mockGetPixels.mockResolvedValue(Buffer.alloc(12).toString('base64'));
    await expect(Image.getColors('https://x/a.jpg')).resolves.toBeNull();
  });

  it('resolves null for an empty source without calling native', async () => {
    await expect(Image.getColors(null)).resolves.toBeNull();
    expect(mockGetPixels).not.toHaveBeenCalled();
  });
});
