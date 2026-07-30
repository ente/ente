Pod::Spec.new do |s|
  s.name             = 'scoped_dir_access'
  s.version          = '1.0.0'
  s.summary          = 'Cross-platform directory utilities with persistent access support'
  s.description      = <<-DESC
Cross-platform directory utilities providing security-scoped bookmark support on macOS
for persistent file access to user-selected directories outside the app sandbox.
                       DESC
  s.homepage         = 'https://github.com/ente/ente'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ente' => 'support@ente.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.14'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
