require "fileutils"
require "open3"
require "rbconfig"
require "tmpdir"

CHECK = File.expand_path("check.rb", __dir__)

def run(files)
  Dir.mktmpdir("ente-workflow-security-") do |root|
    files.each do |path, source|
      destination = "#{root}/#{path}"
      FileUtils.mkdir_p(File.dirname(destination))
      File.write(destination, source)
    end
    Open3.capture3(RbConfig.ruby, CHECK, chdir: root)
  end
end

approval = ".github/workflows/pr-approval.yml"
stdout, stderr, status = run(approval => "on: pull_request_target\n")
raise "#{stdout}#{stderr}" unless status.success?

{
  ".github/workflows/other.yml" => "on: [pull_request_target]\n",
  ".github/workflows/pr-approval.yaml" => "on:\n  pull_request_target:\n",
}.each do |path, source|
  stdout, stderr, status = run(approval => "on: pull_request_target\n", path => source)
  raise "#{stdout}#{stderr}" unless status.exitstatus == 1 && stdout.include?("#{path}: pull_request_target")
end

stdout, stderr, status = run(approval => <<~YAML)
  on: [pull_request_target, workflow_run]
  jobs:
    approve:
      steps:
        - uses: actions/github-script@v9
YAML
raise "#{stdout}#{stderr}" unless status.exitstatus == 1
["workflow_run", "actions/github-script@v9"].each do |violation|
  raise stdout unless stdout.include?("#{approval}: #{violation}")
end
raise stdout if stdout.include?("#{approval}: pull_request_target")
