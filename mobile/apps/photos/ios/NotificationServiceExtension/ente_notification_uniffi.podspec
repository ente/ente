Pod::Spec.new do |s|
  s.name = 'ente_notification_uniffi'
  s.version = '0.1.0'
  s.summary = 'Native notification decryption for Ente Photos.'
  s.homepage = 'https://github.com/ente/ente'
  s.license = { :type => 'AGPL-3.0' }
  s.author = 'Ente'
  s.source = { :path => '.' }
  s.platform = :ios, '15.1'
  s.static_framework = true
  s.source_files = 'Generated/ente_notification_uniffiFFI.h'

  s.script_phase = {
    :name => 'Build notification Rust library',
    :script => 'sh "$(cd -P "$PODS_TARGET_SRCROOT" && pwd)/../../../../cargokit/build_pod.sh" ../../../../../rust/bindings/uniffi/notifications ente_notification_uniffi',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${PODS_CONFIGURATION_BUILD_DIR}/ente_notification_uniffi/libente_notification_uniffi.a'],
  }
  s.user_target_xcconfig = {
    'LIBRARY_SEARCH_PATHS' => '$(inherited) "${PODS_CONFIGURATION_BUILD_DIR}/ente_notification_uniffi"',
    'OTHER_LDFLAGS' => '$(inherited) -lente_notification_uniffi',
  }
end
