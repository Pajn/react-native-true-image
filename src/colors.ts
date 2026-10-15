/* eslint-disable no-bitwise -- packing 5-bit colour channels */
import type { ImageColors } from './types';

// Colour extraction modelled on AndroidX Palette, so the swatches match what
// Android developers expect: a 5-bit-per-channel histogram, a modified median
// cut down to 16 colours, Palette's default filter, and its six targets with
// its scoring weights. It runs in JS on the RGBA samples both platforms
// return, so iOS and Android agree for the same pixels. One deliberate
// difference: a swatch is the mean of the original 8-bit pixels it holds
// rather than its 5-bit bin widened back to 8 bits, which reads up to 7
// levels dark per channel.

/** Swatches the median cut stops at; Palette's default. */
const MAX_COLORS = 16;
/** Pixels with less alpha than this are treated as transparent and skipped. */
const MIN_ALPHA = 128;

const BITS = 5;
const SHIFT = 8 - BITS;
const MASK = (1 << BITS) - 1;

interface Swatch {
  r: number;
  g: number;
  b: number;
  population: number;
  hsl: Hsl;
}

/** Hue in degrees, saturation and lightness in 0–1, as Android's ColorUtils. */
type Hsl = readonly [number, number, number];

interface Target {
  key: Exclude<keyof ImageColors, 'dominant'>;
  saturation: readonly [min: number, target: number, max: number];
  lightness: readonly [min: number, target: number, max: number];
}

const VIBRANT_SATURATION = [0.35, 1, 1] as const;
const MUTED_SATURATION = [0, 0.3, 0.4] as const;
const LIGHT = [0.55, 0.74, 1] as const;
const NORMAL = [0.3, 0.5, 0.7] as const;
const DARK = [0, 0.26, 0.45] as const;

/** Palette's targets, in the order it fills them. */
const TARGETS: readonly Target[] = [
  { key: 'lightVibrant', saturation: VIBRANT_SATURATION, lightness: LIGHT },
  { key: 'vibrant', saturation: VIBRANT_SATURATION, lightness: NORMAL },
  { key: 'darkVibrant', saturation: VIBRANT_SATURATION, lightness: DARK },
  { key: 'lightMuted', saturation: MUTED_SATURATION, lightness: LIGHT },
  { key: 'muted', saturation: MUTED_SATURATION, lightness: NORMAL },
  { key: 'darkMuted', saturation: MUTED_SATURATION, lightness: DARK },
];

const SATURATION_WEIGHT = 0.24;
const LIGHTNESS_WEIGHT = 0.52;
const POPULATION_WEIGHT = 0.24;

/**
 * The palette of row-major RGBA pixels (8-bit, not premultiplied). Null when
 * no pixel is opaque enough to count. `dominant` is the most populous swatch,
 * or the mean colour when the filter removed every pixel.
 */
export function paletteFromPixels(pixels: Uint8Array): ImageColors | null {
  const histogram = new Histogram();
  let visible = 0;
  let r = 0;
  let g = 0;
  let b = 0;
  for (let i = 0; i + 3 < pixels.length; i += 4) {
    if (pixels[i + 3]! < MIN_ALPHA) continue;
    const pr = pixels[i]!;
    const pg = pixels[i + 1]!;
    const pb = pixels[i + 2]!;
    visible++;
    r += pr;
    g += pg;
    b += pb;
    histogram.add(pr, pg, pb);
  }
  if (visible === 0) return null;

  const swatches = quantize(histogram);
  let dominant: Swatch | undefined;
  for (const swatch of swatches) {
    if (!dominant || swatch.population > dominant.population) {
      dominant = swatch;
    }
  }
  const colors: ImageColors = {
    dominant: dominant
      ? hex(dominant)
      : hex({ r: r / visible, g: g / visible, b: b / visible }),
    vibrant: null,
    lightVibrant: null,
    darkVibrant: null,
    muted: null,
    lightMuted: null,
    darkMuted: null,
  };
  const maxPopulation = dominant?.population ?? 1;
  // By colour, as Palette does, so two swatches of one colour count as one.
  const used = new Set<string>();
  for (const target of TARGETS) {
    let best: Swatch | undefined;
    let bestScore = 0;
    for (const swatch of swatches) {
      if (used.has(hex(swatch)) || !fits(swatch.hsl, target)) continue;
      const score = scoreFor(swatch, target, maxPopulation);
      if (!best || score > bestScore) {
        best = swatch;
        bestScore = score;
      }
    }
    if (best) {
      const color = hex(best);
      colors[target.key] = color;
      used.add(color);
    }
  }
  return colors;
}

/** Decodes base64 with the runtime's `atob` when it has one (Hermes does). */
export function decodeBase64(value: string): Uint8Array {
  const { atob } = globalThis as { atob?: (data: string) => string };
  if (typeof atob === 'function') {
    const binary = atob(value);
    const bytes = new Uint8Array(binary.length);
    for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
    return bytes;
  }
  return decodeBase64Fallback(value);
}

const ALPHABET =
  'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';

/** Exported for tests. Ignores padding and anything outside the alphabet. */
export function decodeBase64Fallback(value: string): Uint8Array {
  const bytes = new Uint8Array(Math.floor((value.length * 3) / 4));
  let length = 0;
  let buffer = 0;
  let bits = 0;
  for (let i = 0; i < value.length; i++) {
    const digit = ALPHABET.indexOf(value.charAt(i));
    if (digit < 0) continue;
    buffer = (buffer << 6) | digit;
    bits += 6;
    if (bits >= 8) {
      bits -= 8;
      bytes[length++] = (buffer >> bits) & 0xff;
    }
  }
  return bytes.subarray(0, length);
}

/** Pixel counts and 8-bit channel sums per 5-bit colour. */
class Histogram {
  readonly count = new Uint32Array(1 << (BITS * 3));
  readonly r = new Float64Array(1 << (BITS * 3));
  readonly g = new Float64Array(1 << (BITS * 3));
  readonly b = new Float64Array(1 << (BITS * 3));

  add(r: number, g: number, b: number) {
    const bin =
      ((r >> SHIFT) << (BITS * 2)) | ((g >> SHIFT) << BITS) | (b >> SHIFT);
    this.count[bin]!++;
    this.r[bin]! += r;
    this.g[bin]! += g;
    this.b[bin]! += b;
  }
}

/** One 5-bit channel of a bin: 0 red, 1 green, 2 blue. */
function channel(bin: number, which: number): number {
  return (bin >> (BITS * (2 - which))) & MASK;
}

/** A range of `bins` and the bounding box of the colours in it. */
class Box {
  min = [0, 0, 0];
  max = [0, 0, 0];
  population = 0;

  constructor(
    private readonly bins: number[],
    private readonly histogram: Histogram,
    readonly lower: number,
    public upper: number
  ) {
    this.fit();
  }

  get volume(): number {
    return (
      (this.max[0]! - this.min[0]! + 1) *
      (this.max[1]! - this.min[1]! + 1) *
      (this.max[2]! - this.min[2]! + 1)
    );
  }

  get canSplit(): boolean {
    return this.upper > this.lower;
  }

  fit() {
    this.min = [MASK, MASK, MASK];
    this.max = [0, 0, 0];
    this.population = 0;
    for (let i = this.lower; i <= this.upper; i++) {
      const bin = this.bins[i]!;
      this.population += this.histogram.count[bin]!;
      for (let c = 0; c < 3; c++) {
        const value = channel(bin, c);
        if (value < this.min[c]!) this.min[c] = value;
        if (value > this.max[c]!) this.max[c] = value;
      }
    }
  }

  /**
   * Sorts the range along its longest side and splits it where half the
   * population is reached. This box keeps the lower half.
   */
  split(): Box {
    const sides = [0, 1, 2].map((c) => this.max[c]! - this.min[c]!);
    const longest =
      sides[0]! >= sides[1]! && sides[0]! >= sides[2]!
        ? 0
        : sides[1]! >= sides[0]! && sides[1]! >= sides[2]!
          ? 1
          : 2;
    // Order by the longest side first and the others after, as Palette's
    // significant-octet swap does.
    const order = [longest, ...[0, 1, 2].filter((c) => c !== longest)];
    const key = (bin: number) =>
      (channel(bin, order[0]!) << (BITS * 2)) |
      (channel(bin, order[1]!) << BITS) |
      channel(bin, order[2]!);
    const range = this.bins
      .slice(this.lower, this.upper + 1)
      .sort((a, b) => key(a) - key(b));
    this.bins.splice(this.lower, range.length, ...range);

    const midpoint = this.population / 2;
    let splitAt = this.lower;
    for (let i = this.lower, count = 0; i <= this.upper; i++) {
      count += this.histogram.count[this.bins[i]!]!;
      if (count >= midpoint) {
        splitAt = Math.min(this.upper - 1, i);
        break;
      }
    }
    const upper = new Box(this.bins, this.histogram, splitAt + 1, this.upper);
    this.upper = splitAt;
    this.fit();
    return upper;
  }

  swatch(): Swatch {
    let r = 0;
    let g = 0;
    let b = 0;
    for (let i = this.lower; i <= this.upper; i++) {
      const bin = this.bins[i]!;
      r += this.histogram.r[bin]!;
      g += this.histogram.g[bin]!;
      b += this.histogram.b[bin]!;
    }
    return makeSwatch(
      r / this.population,
      g / this.population,
      b / this.population,
      this.population
    );
  }
}

function quantize(histogram: Histogram): Swatch[] {
  const bins: number[] = [];
  const swatches: Swatch[] = [];
  for (let bin = 0; bin < histogram.count.length; bin++) {
    const count = histogram.count[bin]!;
    if (count === 0) continue;
    const swatch = makeSwatch(
      histogram.r[bin]! / count,
      histogram.g[bin]! / count,
      histogram.b[bin]! / count,
      count
    );
    if (isFiltered(swatch.hsl)) continue;
    bins.push(bin);
    swatches.push(swatch);
  }
  if (bins.length <= MAX_COLORS) return swatches;
  // Split the largest box by volume until there are enough or none splits.
  const boxes = [new Box(bins, histogram, 0, bins.length - 1)];
  while (boxes.length < MAX_COLORS) {
    let largest = -1;
    for (let i = 0; i < boxes.length; i++) {
      if (
        boxes[i]!.canSplit &&
        (largest < 0 || boxes[i]!.volume > boxes[largest]!.volume)
      ) {
        largest = i;
      }
    }
    if (largest < 0) break;
    boxes.push(boxes[largest]!.split());
  }
  return boxes.map((box) => box.swatch()).filter((s) => !isFiltered(s.hsl));
}

function makeSwatch(
  r: number,
  g: number,
  b: number,
  population: number
): Swatch {
  const rr = Math.round(r);
  const gg = Math.round(g);
  const bb = Math.round(b);
  return { r: rr, g: gg, b: bb, population, hsl: toHsl(rr, gg, bb) };
}

/** Palette's default filter: near black, near white, and the red 'I' line. */
function isFiltered([h, s, l]: Hsl): boolean {
  return l <= 0.05 || l >= 0.95 || (h >= 10 && h <= 37 && s <= 0.82);
}

function fits([, s, l]: Hsl, target: Target): boolean {
  return (
    s >= target.saturation[0] &&
    s <= target.saturation[2] &&
    l >= target.lightness[0] &&
    l <= target.lightness[2]
  );
}

function scoreFor(
  swatch: Swatch,
  target: Target,
  maxPopulation: number
): number {
  const [, s, l] = swatch.hsl;
  return (
    SATURATION_WEIGHT * (1 - Math.abs(s - target.saturation[1])) +
    LIGHTNESS_WEIGHT * (1 - Math.abs(l - target.lightness[1])) +
    POPULATION_WEIGHT * (swatch.population / maxPopulation)
  );
}

/** Android's ColorUtils.RGBToHSL. */
function toHsl(r: number, g: number, b: number): Hsl {
  const rf = r / 255;
  const gf = g / 255;
  const bf = b / 255;
  const max = Math.max(rf, gf, bf);
  const min = Math.min(rf, gf, bf);
  const delta = max - min;
  const l = (max + min) / 2;
  if (delta === 0) return [0, 0, l];
  let h: number;
  if (max === rf) h = ((gf - bf) / delta) % 6;
  else if (max === gf) h = (bf - rf) / delta + 2;
  else h = (rf - gf) / delta + 4;
  h = (h * 60) % 360;
  if (h < 0) h += 360;
  const s = delta / (1 - Math.abs(2 * l - 1));
  return [h, Math.min(1, Math.max(0, s)), l];
}

function hex({ r, g, b }: { r: number; g: number; b: number }): string {
  const part = (value: number) =>
    Math.round(value).toString(16).padStart(2, '0');
  return `#${part(r)}${part(g)}${part(b)}`;
}
