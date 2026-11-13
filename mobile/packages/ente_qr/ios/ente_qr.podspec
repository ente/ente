Pod::Spec.new do |s|
  s.name             = 'ente_qr'
  s.version          = '0.0.1'
  s.summary          = 'A QR code reader plugin for Ente.'
  s.description      = <<-DESC
A QR code reader plugin for Ente.
                       DESC
  s.homepage         = 'https://ente.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ente' => 'team@ente.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '9.0'

  # Flutter.framework does not contain a i386 slice.
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
