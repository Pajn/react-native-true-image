#import <XCTest/XCTest.h>

#import <ReactCommon/RCTTurboModule.h>
#import <ReactCodegen/RCTModuleProviders.h>
#import <ReactCodegen/RCTThirdPartyComponentsProvider.h>

#import "TrueImageModule.h"

/// The library is reachable from JS through the tables codegen generates
/// from `codegenConfig` in package.json. React Native indexes them with the
/// names the JS specs ask for, so a wrong key builds cleanly and fails only
/// at startup. These tests read the generated tables the example app links.
@interface TrueImageRegistrationTests : XCTestCase
@end

@implementation TrueImageRegistrationTests

- (void)testTurboModuleIsRegisteredUnderTheNameJSAsksFor
{
  // Must match `TurboModuleRegistry.getEnforcing` in src/specs/NativeTrueImage.ts.
  NSString *jsName = @"TrueImage";
  id<RCTModuleProvider> provider = RCTModuleProviders.moduleProviders[jsName];
  XCTAssertNotNil(provider, @"no module provider is registered for %@; registered: %@", jsName,
                  RCTModuleProviders.moduleProviders.allKeys);
  XCTAssertTrue([provider isKindOfClass:TrueImageModule.class]);
  XCTAssertEqualObjects([TrueImageModule moduleName], jsName);
}

- (void)testComponentIsRegisteredUnderTheNameJSAsksFor
{
  // Must match `codegenNativeComponent` in src/specs/TrueImageViewNativeComponent.ts.
  NSString *jsName = @"TrueImageView";
  Class componentClass = RCTThirdPartyComponentsProvider.thirdPartyFabricComponents[jsName];
  XCTAssertNotNil(componentClass, @"no component is registered for %@; registered: %@", jsName,
                  RCTThirdPartyComponentsProvider.thirdPartyFabricComponents.allKeys);
  XCTAssertEqualObjects(NSStringFromClass(componentClass), @"TrueImageComponentView");
}

@end
