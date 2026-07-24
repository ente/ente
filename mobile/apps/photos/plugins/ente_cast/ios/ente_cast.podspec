Pod::Spec.new do |s|
  s.name             = 'ente_cast'
  s.version          = '0.0.1'
  s.summary          = 'Chromecast sender transport for Ente.'
  s.homepage         = 'https://ente.com'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'code@ente.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform         = :ios, '15.1'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
