import { describe, expect, it } from '@jest/globals';
import {
  decodeBase64,
  decodeBase64Fallback,
  paletteFromPixels,
} from '../colors';

type Rgba = readonly [number, number, number, number?];

/** `count` pixels of each colour in turn; alpha defaults to opaque. */
function pixels(...runs: [Rgba, number][]): Uint8Array {
  const total = runs.reduce((sum, [, count]) => sum + count, 0);
  const bytes = new Uint8Array(total * 4);
  let offset = 0;
  for (const [[r, g, b, a = 255], count] of runs) {
    for (let i = 0; i < count; i++) {
      bytes.set([r, g, b, a], offset);
      offset += 4;
    }
  }
  return bytes;
}

describe('paletteFromPixels', () => {
  it('reports a single colour exactly as the dominant colour', () => {
    const colors = paletteFromPixels(pixels([[30, 90, 200], 2304]));
    expect(colors?.dominant).toBe('#1e5ac8');
  });

  it('assigns a saturated mid colour to vibrant only', () => {
    expect(paletteFromPixels(pixels([[30, 90, 200], 100]))).toEqual({
      dominant: '#1e5ac8',
      vibrant: '#1e5ac8',
      lightVibrant: null,
      darkVibrant: null,
      muted: null,
      lightMuted: null,
      darkMuted: null,
    });
  });

  it('picks the larger half of a two-colour split as dominant', () => {
    const colors = paletteFromPixels(
      pixels([[200, 40, 60], 1000], [[40, 60, 200], 1304])
    );
    expect(colors?.dominant).toBe('#283cc8');
  });

  it('gives each target a different colour', () => {
    const colors = paletteFromPixels(
      pixels(
        [[230, 50, 80], 400], // vibrant
        [[250, 150, 200], 400], // light vibrant
        [[90, 10, 120], 400], // dark vibrant
        [[150, 120, 160], 400], // muted
        [[200, 190, 210], 400], // light muted
        [[60, 50, 70], 400] // dark muted
      )
    );
    expect(colors).toEqual({
      dominant: expect.any(String),
      vibrant: '#e63250',
      lightVibrant: '#fa96c8',
      darkVibrant: '#5a0a78',
      muted: '#9678a0',
      lightMuted: '#c8bed2',
      darkMuted: '#3c3246',
    });
  });

  it('never gives one colour to two targets', () => {
    const colors = paletteFromPixels(pixels([[150, 120, 160], 100]))!;
    const named = Object.entries(colors).filter(
      ([key, value]) => key !== 'dominant' && value !== null
    );
    expect(named).toEqual([['muted', '#9678a0']]);
  });

  it('filters near black and near white out of the swatches', () => {
    const colors = paletteFromPixels(
      pixels([[0, 0, 0], 1000], [[255, 255, 255], 1000], [[30, 90, 200], 50])
    );
    expect(colors?.dominant).toBe('#1e5ac8');
  });

  it('filters the red I line Palette ignores', () => {
    // Hue 24°, saturation 0.6: skin-like tones Palette never picks.
    const colors = paletteFromPixels(
      pixels([[200, 120, 70], 1000], [[30, 90, 200], 50])
    );
    expect(colors?.dominant).toBe('#1e5ac8');
  });

  it('falls back to the mean colour when every pixel is filtered', () => {
    expect(
      paletteFromPixels(pixels([[0, 0, 0], 100], [[255, 255, 255], 100]))
    ).toEqual({
      dominant: '#808080',
      vibrant: null,
      lightVibrant: null,
      darkVibrant: null,
      muted: null,
      lightMuted: null,
      darkMuted: null,
    });
  });

  it('skips transparent pixels', () => {
    const colors = paletteFromPixels(
      pixels([[200, 40, 60, 0], 2000], [[30, 90, 200], 304])
    );
    expect(colors?.dominant).toBe('#1e5ac8');
  });

  it('returns null without an opaque pixel', () => {
    expect(paletteFromPixels(new Uint8Array(0))).toBeNull();
    expect(paletteFromPixels(pixels([[200, 40, 60, 0], 100]))).toBeNull();
  });

  it('reduces many colours to at most 16 swatches', () => {
    // A gradient over every hue: far more 5-bit colours than swatches.
    const runs: [Rgba, number][] = [];
    for (let i = 0; i < 48 * 48; i++) {
      const t = i / (48 * 48);
      runs.push([
        [
          Math.round(127 + 100 * Math.sin(t * 6.28)),
          Math.round(127 + 100 * Math.sin(t * 6.28 + 2.09)),
          Math.round(127 + 100 * Math.sin(t * 6.28 + 4.19)),
        ],
        1,
      ]);
    }
    const colors = paletteFromPixels(pixels(...runs))!;
    expect(colors.dominant).toMatch(/^#[0-9a-f]{6}$/);
    const named = Object.values(colors).filter((value) => value !== null);
    expect(new Set(named.slice(1)).size).toBe(named.length - 1);
    expect(colors.vibrant).not.toBeNull();
  });
});

describe('decodeBase64', () => {
  const encoded = Buffer.from([0, 1, 127, 128, 254, 255, 42]).toString(
    'base64'
  );

  it('decodes with the global atob', () => {
    expect(Array.from(decodeBase64(encoded))).toEqual([
      0, 1, 127, 128, 254, 255, 42,
    ]);
  });

  it('decodes without atob, with and without padding', () => {
    expect(Array.from(decodeBase64Fallback(encoded))).toEqual([
      0, 1, 127, 128, 254, 255, 42,
    ]);
    expect(Array.from(decodeBase64Fallback(encoded.split('=')[0]!))).toEqual([
      0, 1, 127, 128, 254, 255, 42,
    ]);
    expect(Array.from(decodeBase64Fallback(''))).toEqual([]);
  });
});
