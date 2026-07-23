#!/usr/bin/env ruby

require "yaml"

SECTIONS = %w[dependencies dev_dependencies dependency_overrides].freeze
FULL_SHA = /\A[0-9a-f]{40}\z/.freeze
SPECIAL_VERSION_TOKENS = %w[any].freeze

def lock_package(lock_data, name)
  (lock_data["packages"] || {})[name]
end

def floating_version?(value)
  SPECIAL_VERSION_TOKENS.include?(value) || value.match?(/[<>=^*]/)
end

def validate_string_spec(errors, pubspec, section, name, spec, locked)
  if spec.empty? || floating_version?(spec)
    errors << "#{pubspec}: #{section}.#{name} must be an exact version, found #{spec.inspect}"
    return
  end

  if locked.nil?
    errors << "#{pubspec}: #{section}.#{name} has no matching lockfile entry"
    return
  end

  if locked["source"] != "hosted"
    errors << "#{pubspec}: #{section}.#{name} must match #{locked['source']} lockfile source"
    return
  end

  if spec != locked["version"]
    errors << "#{pubspec}: #{section}.#{name} is #{spec.inspect}, lockfile resolves #{locked['version'].inspect}"
  end
end

def validate_git_spec(errors, pubspec, section, name, spec, locked)
  git = spec["git"]
  unless git.is_a?(Hash)
    errors << "#{pubspec}: #{section}.#{name} must use structured git syntax with url/ref"
    return
  end

  ref = git["ref"]
  unless ref.is_a?(String) && ref.match?(FULL_SHA)
    errors << "#{pubspec}: #{section}.#{name} git ref must be a full 40-char SHA"
    return
  end

  if locked.nil?
    errors << "#{pubspec}: #{section}.#{name} has no matching lockfile entry"
    return
  end

  if locked["source"] != "git"
    errors << "#{pubspec}: #{section}.#{name} must match git lockfile source"
    return
  end

  desc = locked["description"] || {}
  resolved_ref = desc["resolved-ref"] || desc["ref"]
  lock_path = desc["path"] || "."
  spec_path = git["path"] || "."

  if git["url"] != desc["url"]
    errors << "#{pubspec}: #{section}.#{name} git url does not match lockfile"
  end

  if spec_path != lock_path
    errors << "#{pubspec}: #{section}.#{name} git path #{spec_path.inspect} does not match lockfile #{lock_path.inspect}"
  end

  if ref != resolved_ref
    errors << "#{pubspec}: #{section}.#{name} git ref does not match resolved lockfile SHA"
  end
end

def validate_spec(errors, pubspec, section, name, spec, locked)
  case spec
  when String
    validate_string_spec(errors, pubspec, section, name, spec, locked)
  when NilClass
    errors << "#{pubspec}: #{section}.#{name} must be pinned explicitly, found a blank dependency entry"
  when Hash
    return if spec.key?("path") || spec.key?("sdk")

    if spec.key?("git")
      validate_git_spec(errors, pubspec, section, name, spec, locked)
    else
      errors << "#{pubspec}: #{section}.#{name} uses unsupported dependency syntax"
    end
  else
    errors << "#{pubspec}: #{section}.#{name} uses unsupported dependency syntax"
  end
end

def validate_pubspec(errors, pubspec, lock_data)
  pubspec_data = YAML.load_file(pubspec)

  SECTIONS.each do |section|
    next unless pubspec_data[section].is_a?(Hash)

    pubspec_data[section].each do |name, spec|
      locked = lock_package(lock_data, name)
      validate_spec(errors, pubspec, section, name, spec, locked)
    end
  end
end

workspace_root = ARGV[0] || "mobile"
root_pubspec = File.join(workspace_root, "pubspec.yaml")
root_lock = File.join(workspace_root, "pubspec.lock")

unless File.exist?(root_pubspec) && File.exist?(root_lock)
  warn "Workspace root pubspec.yaml/pubspec.lock not found under #{workspace_root.inspect}."
  exit 1
end

root_lock_data = YAML.load_file(root_lock)
members = YAML.load_file(root_pubspec)["workspace"] || []

targets = [root_pubspec]
targets += members.map { |m| File.join(workspace_root, m, "pubspec.yaml") }
targets += Dir[File.join(workspace_root, "**", "pubspec.lock")].map { |l| l.sub(/\.lock\z/, ".yaml") }
targets.uniq!

errors = []
targets.each do |pubspec|
  sibling_lock = pubspec.sub(/\.yaml\z/, ".lock")
  lock_data = File.exist?(sibling_lock) ? YAML.load_file(sibling_lock) : root_lock_data
  validate_pubspec(errors, pubspec, lock_data)
end

if errors.empty?
  puts "Verified frozen pubspecs for #{targets.size} package(s)."
  exit 0
end

warn "Frozen pubspec policy violations:"
errors.each { |error| warn "  - #{error}" }
exit 1
