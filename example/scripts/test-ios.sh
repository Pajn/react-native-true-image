#!/usr/bin/env bash
# Runs the iOS view, prefetch and registration tests (an XCTest bundle
# hosted by the example app) on the first available iPhone simulator of the newest
# installed runtime. Requires Xcode with a simulator runtime and the pods
# installed in example/ios.
set -euo pipefail
cd "$(dirname "$0")/../ios"

udid=$(xcrun simctl list devices available -j | node -e '
  const { devices } = JSON.parse(require("fs").readFileSync(0, "utf8"));
  const runtimes = Object.keys(devices).sort().reverse();
  for (const runtime of runtimes) {
    const phone = devices[runtime].find((d) => /^iPhone/.test(d.name));
    if (phone) { console.log(phone.udid); process.exit(0); }
  }
  console.error("No iPhone simulator is available");
  process.exit(1);
')

xcodebuild test \
  -workspace TrueImageExample.xcworkspace \
  -scheme TrueImageExample \
  -destination "platform=iOS Simulator,id=$udid" \
  -only-testing:TrueImageTests \
  -quiet
