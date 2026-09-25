Pod::Spec.new do |s|
  s.name             = 'ente_panorama_viewer'
  s.version          = '0.0.1'
  s.summary          = 'First-party panorama rendering and motion support for Ente Photos.'
  s.homepage         = 'https://ente.com'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'code@ente.com' }
  s.source           = { :path => '.' }
  s.source_files     = 'ente_panorama_viewer/Sources/ente_panorama_viewer/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'CoreMotion'
  s.platform         = :ios, '15.1'
  s.swift_version    = '5.0'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
