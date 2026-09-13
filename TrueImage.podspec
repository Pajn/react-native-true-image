require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

Pod::Spec.new do |s|
  s.name         = "TrueImage"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = package["author"]

  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/pajn/react-native-true-image.git", :tag => "#{s.version}" }

  s.source_files = "ios/**/*.{h,m,mm,swift}"
  s.exclude_files = "ios/Tests/**/*"
  # The loader header is the one Objective-C surface the Swift view uses.
  s.public_header_files = "ios/TrueImageLoader.h"
  s.private_header_files = [
    "ios/TrueImageComponentView.h",
    "ios/TrueImageModule.h",
    "ios/TrueImageWebPCoder.h",
  ]
  s.swift_version = "5.9"

  # The Objective-C++ Fabric shell reaches the Swift view through the
  # generated TrueImage-Swift.h, which needs the pod built as a module.
  s.pod_target_xcconfig = {
    "DEFINES_MODULE" => "YES",
  }

  s.dependency "SDWebImage", "~> 5.21"

  install_modules_dependencies(s)
end
