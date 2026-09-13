import { describe, expect, it } from '@jest/globals';
import { readFileSync, readdirSync } from 'fs';
import { join } from 'path';

// Codegen registers the iOS TurboModule under the key in
// `codegenConfig.ios.modulesProvider`, and React Native looks it up by the
// name JS passes to `TurboModuleRegistry.getEnforcing`. Nothing at build
// time checks that the two agree: a mismatch compiles, links and fails only
// when the app starts. This test makes that a test failure instead.

const root = join(__dirname, '..', '..');
const specsDir = join(root, 'src', 'specs');
const iosDir = join(root, 'ios');

type CodegenConfig = {
  ios: {
    components: Record<string, { className: string }>;
    modulesProvider: Record<string, string>;
  };
};

const { codegenConfig } = JSON.parse(
  readFileSync(join(root, 'package.json'), 'utf8')
) as { codegenConfig: CodegenConfig };

function readSpecs(): string[] {
  return readdirSync(specsDir).map((name) =>
    readFileSync(join(specsDir, name), 'utf8')
  );
}

function matchAll(sources: string[], pattern: RegExp): string[] {
  return sources.flatMap((source) =>
    Array.from(source.matchAll(pattern), (match) => match[1] as string)
  );
}

function iosSourceDefines(className: string): boolean {
  const pattern = new RegExp(`@implementation\\s+${className}\\b`);
  return readdirSync(iosDir)
    .filter((name) => /\.mm?$/.test(name))
    .some((name) => pattern.test(readFileSync(join(iosDir, name), 'utf8')));
}

describe('codegenConfig', () => {
  const specs = readSpecs();
  const moduleNames = matchAll(
    specs,
    /TurboModuleRegistry\.getEnforcing<[^>]*>\(\s*'([^']+)'/g
  );
  const componentNames = matchAll(
    specs,
    /codegenNativeComponent<[^>]*>\(\s*'([^']+)'/g
  );

  it('finds the specs', () => {
    expect(moduleNames).toEqual(['TrueImage']);
    expect(componentNames).toEqual(['TrueImageView']);
  });

  it('registers every TurboModule on iOS under the name JS asks for', () => {
    expect(Object.keys(codegenConfig.ios.modulesProvider).sort()).toEqual(
      [...moduleNames].sort()
    );
  });

  it('registers every component on iOS under the name JS asks for', () => {
    expect(Object.keys(codegenConfig.ios.components).sort()).toEqual(
      [...componentNames].sort()
    );
  });

  it('maps every iOS registration to a class the library defines', () => {
    const classes = [
      ...Object.values(codegenConfig.ios.modulesProvider),
      ...Object.values(codegenConfig.ios.components).map((c) => c.className),
    ];
    for (const className of classes) {
      expect(iosSourceDefines(className)).toBe(true);
    }
  });
});
