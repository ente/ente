Pod::Spec.new do |s|
  s.name = 'ente_background_manager'
  s.version = '0.0.1'
  s.summary = 'Native background scheduling and headless task lifecycle.'
  s.homepage = 'https://ente.com'
  s.license = { :type => 'AGPL-3.0-only' }
  s.author = { 'Ente' => 'code@ente.com' }
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.1'
  s.swift_version = '5.0'
  s.frameworks = 'BackgroundTasks'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }
end
