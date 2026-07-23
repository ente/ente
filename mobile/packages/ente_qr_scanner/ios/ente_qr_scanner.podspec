Pod::Spec.new do |s|
  s.name             = 'ente_qr_scanner'
  s.version          = '0.0.1'
  s.summary          = 'Live QR scanner plugin for Ente mobile apps.'
  s.description      = <<-DESC
Live QR scanner plugin for Ente mobile apps using AVFoundation.
                       DESC
  s.homepage         = 'https://ente.com'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'support@ente.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
