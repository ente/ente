Pod::Spec.new do |s|
  s.name             = 'ente_mail'
  s.version          = '0.0.1'
  s.summary          = 'Ente-owned system mail composition'
  s.homepage         = 'https://github.com/ente-io/ente'
  s.license          = { :type => 'AGPL-3.0-only' }
  s.author           = { 'Ente' => 'support@ente.io' }
  s.source           = { :path => '.' }
  s.source_files     = 'ente_mail/Sources/ente_mail/**/*.swift'
  s.dependency 'Flutter'
  s.frameworks = 'Intents', 'MessageUI'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386'
  }
end
