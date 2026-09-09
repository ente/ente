require "json"
require "open3"
require "pathname"
require "set"
require "yaml"

Dir.chdir(ARGV.fetch(0, "."))
root = Pathname.pwd
workflow_path = ".github/workflows/web-lint.yml"
workflow = YAML.safe_load(File.read(workflow_path), aliases: true)
events = workflow["on"] || workflow[true]
config = events.fetch("pull_request") || {}
abort "#{workflow_path}: WASM coverage does not support paths-ignore" if config.key?("paths-ignore")
patterns = config["paths"]
exit 0 unless patterns
abort "#{workflow_path}: WASM coverage does not support negated paths" if patterns.any? { |p| p.start_with?("!") }

output, status = Open3.capture2(
  "cargo", "metadata", "--no-deps", "--format-version", "1", "--locked", "--offline",
  chdir: "rust",
)
exit status.exitstatus unless status.success?
packages = JSON.parse(output).fetch("packages")
by_name = packages.to_h { |package| [package.fetch("name"), package] }
by_directory = packages.to_h { |package| [Pathname.new(package.fetch("manifest_path")).dirname, package] }
pending = Dir["web/packages/wasm/*/package.json"].map do |path|
  name = JSON.parse(File.read(path)).fetch("name")
  package = by_name.fetch(name) { abort "#{path}: no matching Cargo package for #{name}" }
  Pathname.new(package.fetch("manifest_path")).dirname
end
abort "No Web WASM packages found" if pending.empty?

directories = Set.new
until pending.empty?
  directory = pending.pop
  next unless directories.add?(directory)

  package = by_directory.fetch(directory) { abort "Local dependency #{directory} is outside the Rust workspace" }
  # Include optional and target-specific edges to avoid fetching Cargo's resolved graph.
  package.fetch("dependencies").each do |dependency|
    next if dependency["kind"] == "dev" || !dependency["path"]

    pending << Pathname.new(dependency.fetch("path"))
  end
end

required = %w[rust/Cargo.lock rust/Cargo.toml] + directories.map { |dir| "#{dir.relative_path_from(root)}/**" }
# Literal directory prefixes prove coverage of the entire crate, including future files.
prefixes = patterns.grep(%r{\A[\w./-]+/\*\*\z}).map { |pattern| pattern.delete_suffix("**") }
missing = required.reject { |path| patterns.include?(path) || prefixes.any? { |prefix| path.start_with?(prefix) } }
missing.sort.each { |path| warn "#{workflow_path}: missing WASM dependency path #{path.inspect}" }
exit(missing.empty? ? 0 : 1)
