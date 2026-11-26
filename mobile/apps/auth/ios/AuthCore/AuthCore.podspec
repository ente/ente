Pod::Spec.new do |s|
  s.name = 'AuthCore'
  s.version = '1.0.0'
  s.summary = 'Shared authentication logic for Ente Auth.'
  s.homepage = 'https://ente.io/auth'
  s.license = { :type => 'AGPL-3.0-only', :file => '../../../../../LICENSE' }
  s.author = 'Ente'
  s.source = { :git => 'https://github.com/ente-io/ente.git', :tag => s.version.to_s }
  s.source_files = 'Sources/AuthCore/**/*.swift'
  s.platforms = { :ios => '15.0', :watchos => '10.0' }
  s.swift_version = '6.0'
  s.static_framework = true
end
