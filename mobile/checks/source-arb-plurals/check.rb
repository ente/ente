#!/usr/bin/env ruby

require "json"
require "yaml"

MOBILE_ROOT = File.expand_path("../..", __dir__)
EXACT_ONE_SELECTOR = /=1\s*\{/.freeze

def source_arbs
  Dir[File.join(MOBILE_ROOT, "{apps,packages}/**/l10n.yaml")].sort.map do |config_path|
    config = YAML.load_file(config_path) || {}
    arb_dir = config["arb-dir"]
    template_arb_file = config["template-arb-file"]
    next unless arb_dir.is_a?(String) && template_arb_file.is_a?(String)

    File.join(File.dirname(config_path), arb_dir, template_arb_file)
  end.compact.uniq
end

def display_path(path)
  "mobile/#{path.delete_prefix("#{MOBILE_ROOT}/")}"
end

errors = []

source_arbs.each do |arb_path|
  arb = JSON.parse(File.read(arb_path))

  arb.each do |key, value|
    next if key.start_with?("@")
    next unless value.is_a?(String)
    next unless value.match?(EXACT_ONE_SELECTOR)

    errors << "#{display_path(arb_path)}: #{key} uses =1. Use one{...} in source ARBs; keep exact selectors for cases like =0."
  end
rescue JSON::ParserError => e
  errors << "#{display_path(arb_path)}: invalid JSON: #{e.message}"
end

if errors.empty?
  puts "Verified source ARB plurals."
  exit 0
end

warn "Source ARB plural violations:"
errors.each { |error| warn "  - #{error}" }
exit 1
