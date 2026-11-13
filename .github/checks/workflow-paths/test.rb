require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

CHECK = File.expand_path("check.rb", __dir__)

def run(source)
  Dir.mktmpdir("ente-workflow-paths-") do |root|
    FileUtils.mkdir_p("#{root}/.github/workflows")
    File.write("#{root}/.github/workflows/test.yml", source)
    Open3.capture3(RbConfig.ruby, CHECK, root)
  end
end

[
  "on: [push, pull_request]\n",
  "'on':\n  push:\n    paths: [a/**, b/**]\n",
  "on:\n  push:\n    paths: [z/**, '!z/private/**', a/**]\n",
  "on:\n  push:\n    paths: &paths [a/**, b/**]\n  pull_request:\n    paths: *paths\n",
  <<~YAML,
    on:
      workflow_dispatch:
    jobs:
      check:
        steps:
          - uses: codeql
            with:
              config: |
                paths-ignore: [z/**, a/**]
  YAML
].each do |source|
  stdout, stderr, status = run(source)
  raise stderr unless status.success? && stdout.empty? && stderr.empty?
end

source = <<~YAML
  on:
    push:
      paths: [b/**, a/**]
    pull_request:
      paths-ignore:
        - z/** # comment
        - a/**
YAML
stdout, stderr, status = run(source)
raise stderr unless status.exitstatus == 1 && stdout.empty?
%w[push.paths pull_request.paths-ignore].each do |field|
  expected = ".github/workflows/test.yml: on.#{field} must be sorted"
  raise stderr unless stderr.include?(expected)
end
