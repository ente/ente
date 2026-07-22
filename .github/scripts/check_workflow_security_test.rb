# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "stringio"
require "tmpdir"
require_relative "check_workflow_security"

class WorkflowSecurityCheckerTest < Minitest::Test
  ROOT = File.expand_path("../..", __dir__)

  def test_repository_matches_the_complete_security_contract
    status, output = run_checker(ROOT)

    assert_equal 0, status, output
    assert_includes output, "Checked 7 approved workflow/action files."
  end

  def test_unexpected_and_missing_automation_fail_the_allowlist
    with_fixture do |root|
      File.write(
        File.join(root, ".github/workflows/unapproved.yml"),
        "name: Unapproved\non: workflow_dispatch\npermissions: {}\njobs: {}\n",
      )
      FileUtils.rm(File.join(root, ".github/workflows/dependency-review.yml"))

      status, output = run_checker(root)
      assert_equal 1, status
      assert_includes output, "Unexpected workflow: .github/workflows/unapproved.yml"
      assert_includes output, "Missing workflow: .github/workflows/dependency-review.yml"
    end
  end

  def test_unpinned_actions_secrets_and_checkout_credentials_fail_closed
    with_fixture do |root|
      path = File.join(root, ".github/workflows/codeql.yml")
      source = File.read(path)
        .sub(/actions\/checkout@[0-9a-f]{40}/, "actions/checkout@main")
        .sub("persist-credentials: false", "persist-credentials: true")
        .sub("category: /language:actions", "category: ${{ secrets.CODEQL_CATEGORY }}")
      File.write(path, source)

      status, output = run_checker(root)
      assert_equal 1, status
      assert_includes output, "unpinned action actions/checkout@main"
      assert_includes output, "actions/checkout must set persist-credentials: false"
      assert_includes output, "secret reference is forbidden"
    end
  end

  def test_trigger_permissions_runner_timeout_guard_and_environment_are_exact
    with_fixture do |root|
      path = File.join(root, ".github/workflows/dependency-review.yml")
      source = File.read(path)
        .sub("pull_request:", "pull_request_target:")
        .sub("contents: read", "contents: write")
        .sub("if: github.repository == 'vanton1/ente'", "if: always()")
        .sub("runs-on: ubuntu-24.04", "runs-on: ubuntu-latest")
        .sub("timeout-minutes: 10", "timeout-minutes: 0\n    environment: production")
      File.write(path, source)

      status, output = run_checker(root)
      assert_equal 1, status
      assert_includes output, "privileged trigger pull_request_target"
      assert_includes output, "expected {\"contents\"=>\"read\"}, found {\"contents\"=>\"write\"}"
      assert_includes output, "must fail closed"
      assert_includes output, "unapproved runner \"ubuntu-latest\""
      assert_includes output, "needs a timeout from 1 to 60 minutes"
      assert_includes output, "expected environment nil, found \"production\""
    end
  end

  def test_workflow_identity_jobs_and_stable_pull_request_checks_are_exact
    with_fixture do |root|
      path = File.join(root, ".github/workflows/dependency-review.yml")
      source = File.read(path)
        .sub("name: Dependency review", "name: Renamed check")
        .sub("pull_request:\n", "pull_request:\n    paths:\n      - mobile/**\n")
        .sub("jobs:\n", "jobs:\n  unexpected: {}\n")
      File.write(path, source)

      status, output = run_checker(root)
      assert_equal 1, status
      assert_includes output, "expected name \"Dependency review\", found \"Renamed check\""
      assert_includes output, "pull_request must always create a stable check"
      assert_includes output, "expected jobs dependency-review, found dependency-review, unexpected"
    end
  end

  private

  def run_checker(root)
    output = StringIO.new
    status = WorkflowSecurityChecker.new(root: root, out: output).run
    [status, output.string]
  end

  def with_fixture
    Dir.mktmpdir("workflow-security-") do |root|
      FileUtils.mkdir_p(File.join(root, ".github"))
      FileUtils.cp_r(File.join(ROOT, ".github/workflows"), File.join(root, ".github"))
      FileUtils.cp_r(File.join(ROOT, ".github/actions"), File.join(root, ".github"))
      yield root
    end
  end
end
