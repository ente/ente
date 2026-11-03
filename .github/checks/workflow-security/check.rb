#!/usr/bin/env ruby

require "set"
require "yaml"

SENSITIVE_TRIGGERS = %w[
  pull_request_target
  issue_comment
  pull_request_review_comment
  discussion_comment
  workflow_run
].to_set.freeze
USES_REF = %r{\A([A-Za-z0-9._-]+/[A-Za-z0-9._-]+/\.github/workflows/[^@]+)@(\S+)\z}
FULL_SHA = /\A[0-9a-fA-F]{40}\z/

def workflow_yaml(path)
  YAML.safe_load(
    File.read(path),
    aliases: true,
  ) || {}
rescue Psych::Exception => e
  abort("Failed to parse workflow YAML in #{path}: #{e.message}")
end

def trigger_names(workflow)
  events = workflow["on"] || workflow[true]
  return [events] if events.is_a?(String)
  return events.grep(String) if events.is_a?(Array)
  return events.keys.map(&:to_s) if events.is_a?(Hash)

  []
end

abort("Usage: #{$PROGRAM_NAME}") unless ARGV.empty?

checked_files = Dir.glob(".github/workflows/*.{yml,yaml}").sort
trigger_violations = []
unpinned_workflows = []

checked_files.each do |path|
  workflow = workflow_yaml(path)
  triggers = trigger_names(workflow).to_set & SENSITIVE_TRIGGERS
  triggers.each do |trigger|
    next if %w[.github/workflows/cla.yml .github/workflows/pr-approval.yml].include?(path) && trigger == "pull_request_target"

    trigger_violations << "#{path}: #{trigger}"
  end

  workflow.fetch("jobs", {}).each_value do |job|
    uses = job["uses"]
    next unless uses

    called_workflow, ref = uses.match(USES_REF)&.captures
    next unless called_workflow
    next if ref.match?(FULL_SHA)

    unpinned_workflows << "#{path}: #{uses}"
  end
end

failed = trigger_violations.any? || unpinned_workflows.any?
puts "Workflow Security Checks: #{failed ? "Failed" : "Passed"}"
puts "Checked #{checked_files.length} workflow files."

exit 0 unless failed

unless trigger_violations.empty?
  puts
  puts "Privileged triggers:"
  trigger_violations.each { |violation| puts "- #{violation}" }
end

unless unpinned_workflows.empty?
  puts
  puts "Unpinned external workflows:"
  unpinned_workflows.each { |violation| puts "- #{violation}" }
end

puts
puts "Fix:"
puts "- Remove privileged triggers." if trigger_violations.any?
puts "- Pin external workflows to a full 40-character commit SHA." if unpinned_workflows.any?
exit 1
