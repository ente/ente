require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

CHECK = File.expand_path("check.rb", __dir__)
WORKFLOW = ".github/workflows/web-lint.yml"

def write(root, path, content)
  FileUtils.mkdir_p(File.dirname("#{root}/#{path}"))
  File.write("#{root}/#{path}", content)
end

def crate(root, path, name, dependencies = "")
  write(root, "rust/#{path}/src/lib.rs", "")
  write(root, "rust/#{path}/Cargo.toml", <<~TOML)
    [package]
    name = "#{name}"
    version = "0.1.0"
    edition = "2024"
    #{dependencies}
  TOML
end

def check(root, patterns, errors = [])
  config = patterns ? { "paths" => patterns } : nil
  write(root, WORKFLOW, { "on" => { "pull_request" => config } }.to_yaml)
  stdout, stderr, status = Open3.capture3(RbConfig.ruby, CHECK, root)
  expected = errors.map { |error| "#{WORKFLOW}: #{error}\n" }.join
  raise "#{stdout}#{stderr}" unless stdout.empty? && stderr == expected && status.exitstatus == (errors.empty? ? 0 : 1)
end

Dir.mktmpdir("ente-wasm-ci-paths-") do |root|
  write(root, "rust/Cargo.toml", <<~TOML)
    [workspace]
    resolver = "2"
    members = ["bindings/wasm/*", "crates/*"]
    [workspace.dependencies]
    shared-alias = { package = "shared", path = "crates/shared" }
  TOML
  write(root, "web/packages/wasm/app/package.json", { name: "app-wasm" }.to_json)
  crate(root, "bindings/wasm/app", "app-wasm", <<~TOML)
    [dependencies]
    shared-alias.workspace = true
    [build-dependencies]
    builder = { path = "../../../crates/builder" }
    [dev-dependencies]
    test-only = { path = "../../../crates/test-only" }
  TOML
  crate(root, "crates/shared", "shared", <<~TOML)
    [target.'cfg(windows)'.dependencies]
    leaf = { path = "../leaf", optional = true }
  TOML
  %w[builder leaf test-only native-only].each { |name| crate(root, "crates/#{name}", name) }
  crate(root, "bindings/wasm/unused", "unused-wasm", <<~TOML)
    [dependencies]
    native-only = { path = "../../../crates/native-only" }
  TOML

  base = %w[rust/Cargo.lock rust/Cargo.toml rust/bindings/wasm/**]
  needed = %w[builder leaf shared].map { |name| "rust/crates/#{name}/**" }
  incomplete = base + %w[rust/crates/shared-other/** rust/crates/leaf/Cargo.toml]
  check(root, incomplete, needed.map { |path| "missing WASM dependency path #{path.inspect}" })
  check(root, base + needed)
  check(root, %w[rust/**])
  check(root, nil)
  check(root, base + needed + ["!rust/crates/leaf/private/**"], ["WASM coverage does not support negated paths"])
end
