Pod::Spec.new do |s|
  s.name             = 'ente_screen_brightness'
  s.version          = '0.0.1'
  s.summary          = 'iOS screen brightness control for Ente.'
  s.homepage         = 'https://github.com/ente-io/ente'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'support@ente.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.1'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
