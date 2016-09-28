platform :ios, '10.0'

target 'OTA' do
  use_frameworks!

  pod 'iOSDFULibrary', :git => 'http://github.com/huguesbr/IOS-Pods-DFU-Library', :branch => 'feature/swift2.3'

  pod 'SSZipArchive', :git => "http://github.com/ZipArchive/ZipArchive", :branch => 'swift23'

end

post_install do |installer|
  installer.pods_project.targets.each do |target|
    target.build_configurations.each do |config|
      config.build_settings['SWIFT_VERSION'] = '2.3'
    end
  end
end