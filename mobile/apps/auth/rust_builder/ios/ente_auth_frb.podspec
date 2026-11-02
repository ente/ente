Pod::Spec.new do |s|
  s.name = 'ente_auth_frb'
  s.version = '0.0.1'
  s.summary = 'Rust bindings for Ente Auth.'
  s.homepage = 'https://ente.io/auth'
  s.license = { :type => 'AGPL-3.0' }
  s.author = 'Ente'
  s.source = { :path => '.' }
  s.source_files = 'Classes/**/*'
  s.dependency 'Flutter'
  s.platform = :ios, '15.0'

  s.script_phase = {
    :name => 'Build Rust library',
    :script => 'sh "$(cd -P "$PODS_TARGET_SRCROOT" && pwd)/../../../../cargokit/build_pod.sh" ../../../../../rust/bindings/frb/auth ente_auth_frb',
    :execution_position => :before_compile,
    :input_files => ['${BUILT_PRODUCTS_DIR}/cargokit_phony'],
    :output_files => ['${BUILT_PRODUCTS_DIR}/libente_auth_frb.a'],
  }
  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'OTHER_LDFLAGS' => '-force_load ${BUILT_PRODUCTS_DIR}/libente_auth_frb.a -lc++',
  }
end
