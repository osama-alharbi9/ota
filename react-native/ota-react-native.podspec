require "fileutils"
require "json"

package = JSON.parse(File.read(File.join(__dir__, "package.json")))

# The app's ota.yaml ships inside the app as a resource, so there is one file to
# edit. CocoaPods only bundles files inside the pod, so it is copied here on every
# `pod install`. Run `pod install` again after changing ota.yaml.
ota_yaml = File.join(Pod::Config.instance.installation_root.to_s, "..", "ota.yaml")
generated = File.join(__dir__, "ios", "generated")
FileUtils.mkdir_p(generated)
FileUtils.cp(ota_yaml, generated) if File.exist?(ota_yaml)

Pod::Spec.new do |s|
  s.name         = "ota-react-native"
  s.module_name  = "OtaReactNative"
  s.version      = package["version"]
  s.summary      = package["description"]
  s.homepage     = package["homepage"]
  s.license      = package["license"]
  s.authors      = { "ota contributors" => "https://github.com/osama-alharbi9/ota" }
  s.platforms    = { :ios => min_ios_version_supported }
  s.source       = { :git => "https://github.com/osama-alharbi9/ota.git", :tag => s.version.to_s }

  s.source_files = "ios/*.{h,m,mm}"
  s.public_header_files = "ios/Ota.h"
  s.resources = "ios/generated/ota.yaml"
  s.libraries = "compression"
  s.pod_target_xcconfig = { "DEFINES_MODULE" => "YES" }

  install_modules_dependencies(s)
end
