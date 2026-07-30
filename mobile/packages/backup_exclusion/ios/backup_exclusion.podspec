Pod::Spec.new do |s|
  s.name             = 'backup_exclusion'
  s.version          = '1.0.0'
  s.summary          = 'Exclude app-managed files from iOS backups'
  s.description      = <<-DESC
Marks app-managed files and directories as excluded from iCloud and local
device backups.
                       DESC
  s.homepage         = 'https://github.com/ente/ente'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'Ente' => 'support@ente.com' }
  s.source           = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '13.0'
  s.swift_version = '5.0'

  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
end
