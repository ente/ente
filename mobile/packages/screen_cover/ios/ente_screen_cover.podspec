Pod::Spec.new do |s|
  s.name             = 'ente_screen_cover'
  s.version          = '0.0.1'
  s.summary          = 'Hides app content in the app switcher for Ente.'
  s.homepage         = 'https://ente.com'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'code@ente.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
  s.swift_version = '5.0'
end
