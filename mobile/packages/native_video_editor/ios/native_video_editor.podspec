Pod::Spec.new do |s|
  s.name             = 'native_video_editor'
  s.version          = '0.0.1'
  s.summary          = 'Native video editing operations for iOS'
  s.description      = <<-DESC
Native video editing operations for trim, crop, and rotate without re-encoding.
                       DESC
  s.homepage         = 'https://github.com/ente/ente'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ente' => 'support@ente.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '11.0'
  s.swift_version = '5.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end