# frozen_string_literal: true

require "minitest/autorun"
require "pathname"
require_relative "../lib/upstream_sync"

class FakeRunner
  attr_reader :commands

  def initialize(results)
    @results = results
    @commands = []
  end

  def capture(*argv)
    @commands << argv
    value = @results.fetch(argv) { raise "Unexpected command: #{argv.inspect}" }
    value.is_a?(EnteUpstreamSync::CommandResult) ? value : result(value)
  end

  def run(*argv)
    response = capture(*argv)
    raise EnteUpstreamSync::CommandFailure.new(argv, response) unless response.success?

    response.stdout.strip
  end

  private

  def result(stdout, stderr: "", status: 0)
    EnteUpstreamSync::CommandResult.new(stdout: stdout, stderr: stderr, status: status)
  end
end

class GitHubRepositoryTest < Minitest::Test
  def test_extracts_slug_from_supported_git_urls
    assert_equal "vanton1/ente", EnteUpstreamSync::GitHubRepository.slug("https://github.com/vanton1/ente.git")
    assert_equal "vanton1/ente", EnteUpstreamSync::GitHubRepository.slug("git@github.com:vanton1/ente.git")
    assert_equal "ente/ente", EnteUpstreamSync::GitHubRepository.slug("ssh://git@github.com/ente/ente.git")
  end

  def test_rejects_non_github_urls
    assert_nil EnteUpstreamSync::GitHubRepository.slug("https://example.com/vanton1/ente.git")
    assert_nil EnteUpstreamSync::GitHubRepository.slug("DISABLED")
  end
end

class InspectorTest < Minitest::Test
  FORK_SHA = "1" * 40
  OFFICIAL_SHA = "2" * 40
  MERGE_BASE_SHA = "3" * 40

  def test_reports_ready_repository_and_upstream_drift_without_mutation
    runner = FakeRunner.new(healthy_results)
    report = inspector(runner).check(fetch: false)

    assert report.ready?
    assert report.sync_required?
    assert_equal 3, report.fork_only_commits
    assert_equal 5, report.upstream_only_commits
    refute report.official_contained
    refute report.fetched
    refute runner.commands.any? { |command| command[0, 2] == ["git", "fetch"] }
  end

  def test_dirty_worktree_is_not_ready
    results = healthy_results
    results[["git", "status", "--porcelain", "--untracked-files=all"]] = " M README.md\n"
    report = inspector(FakeRunner.new(results)).check(fetch: false)

    refute report.ready?
    assert_includes report.problems, "Working tree is not clean."
  end

  def test_unsafe_upstream_push_url_is_not_ready
    results = healthy_results
    results[["git", "remote", "get-url", "--push", "upstream"]] = "https://github.com/ente/ente.git\n"
    report = inspector(FakeRunner.new(results)).check(fetch: false)

    refute report.ready?
    assert report.problems.any? { |problem| problem.include?("upstream push URL must be DISABLED") }
  end

  private

  def inspector(runner)
    EnteUpstreamSync::Inspector.new(runner: runner, root: Pathname("/tmp/example"))
  end

  def healthy_results
    {
      ["git", "symbolic-ref", "--quiet", "--short", "HEAD"] => "main\n",
      ["git", "status", "--porcelain", "--untracked-files=all"] => "",
      ["git", "remote", "get-url", "origin"] => "https://github.com/vanton1/ente.git\n",
      ["git", "remote", "get-url", "--push", "origin"] => "git@github.com:vanton1/ente.git\n",
      ["git", "remote", "get-url", "upstream"] => "https://github.com/ente/ente.git\n",
      ["git", "remote", "get-url", "--push", "upstream"] => "DISABLED\n",
      ["git", "rev-parse", "--verify", "main^{commit}"] => "#{FORK_SHA}\n",
      ["git", "rev-parse", "--verify", "origin/main^{commit}"] => "#{FORK_SHA}\n",
      ["git", "rev-parse", "--verify", "upstream/main^{commit}"] => "#{OFFICIAL_SHA}\n",
      ["git", "merge-base", FORK_SHA, OFFICIAL_SHA] => "#{MERGE_BASE_SHA}\n",
      ["git", "rev-list", "--left-right", "--count", "#{FORK_SHA}...#{OFFICIAL_SHA}"] => "3\t5\n",
      ["git", "merge-base", "--is-ancestor", OFFICIAL_SHA, FORK_SHA] => EnteUpstreamSync::CommandResult.new(
        stdout: "",
        stderr: "",
        status: 1,
      ),
    }
  end
end

class FakeInspector
  def initialize(report)
    @report = report
  end

  def check(fetch:)
    @fetch = fetch
    @report
  end
end

class SynchronizerTest < Minitest::Test
  FORK_SHA = "a" * 40
  OFFICIAL_SHA = "b" * 40
  MERGE_SHA = "c" * 40
  BRANCH = "sync/upstream-2026-07-20-#{OFFICIAL_SHA[0, 10]}"

  def test_creates_sha_qualified_branch_and_merges_recorded_official_commit
    runner = FakeRunner.new(
      ["git", "show-ref", "--verify", "--quiet", "refs/heads/#{BRANCH}"] => result(status: 1),
      ["git", "switch", "-c", BRANCH, FORK_SHA] => "",
      ["git", "merge", "--no-ff", "--no-edit", "-m", "Merge official Ente main at #{OFFICIAL_SHA}", OFFICIAL_SHA] => "Merged\n",
      ["git", "merge-base", "--is-ancestor", OFFICIAL_SHA, "HEAD"] => result(status: 0),
      ["git", "rev-parse", "HEAD"] => "#{MERGE_SHA}\n",
    )

    response = synchronizer(runner, ready_report).start(
      fetch: false,
      expected_official_sha: OFFICIAL_SHA,
      date: Date.new(2026, 7, 20),
    )

    assert_equal :merged, response.status
    assert_equal BRANCH, response.branch
    assert_equal MERGE_SHA, response.merge_commit
  end

  def test_existing_branch_stops_without_switching_or_merging
    runner = FakeRunner.new(
      ["git", "show-ref", "--verify", "--quiet", "refs/heads/#{BRANCH}"] => result(status: 0),
    )

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      synchronizer(runner, ready_report).start(fetch: false, date: Date.new(2026, 7, 20))
    end

    assert_includes error.message, "already exists"
    refute runner.commands.any? { |command| command[0, 2] == ["git", "switch"] }
  end

  def test_merge_conflict_preserves_branch_and_reports_files
    runner = FakeRunner.new(
      ["git", "show-ref", "--verify", "--quiet", "refs/heads/#{BRANCH}"] => result(status: 1),
      ["git", "switch", "-c", BRANCH, FORK_SHA] => "",
      ["git", "merge", "--no-ff", "--no-edit", "-m", "Merge official Ente main at #{OFFICIAL_SHA}", OFFICIAL_SHA] => result(
        stdout: "",
        stderr: "CONFLICT",
        status: 1,
      ),
      ["git", "diff", "--name-only", "--diff-filter=U"] => "mobile/example.dart\n",
    )

    error = assert_raises(EnteUpstreamSync::MergeStopped) do
      synchronizer(runner, ready_report).start(fetch: false, date: Date.new(2026, 7, 20))
    end

    assert_equal BRANCH, error.branch
    assert_equal ["mobile/example.dart"], error.conflicts
    refute runner.commands.any? { |command| command == ["git", "merge", "--abort"] }
  end

  def test_mismatched_requested_sha_stops_before_branch_creation
    runner = FakeRunner.new({})

    assert_raises(EnteUpstreamSync::SafetyFailure) do
      synchronizer(runner, ready_report).start(
        fetch: false,
        expected_official_sha: "d" * 40,
        date: Date.new(2026, 7, 20),
      )
    end
    assert_empty runner.commands
  end

  def test_resume_refuses_unresolved_conflicts
    runner = FakeRunner.new(
      ["git", "symbolic-ref", "--quiet", "--short", "HEAD"] => "#{BRANCH}\n",
      ["git", "rev-parse", "--verify", "MERGE_HEAD^{commit}"] => "#{OFFICIAL_SHA}\n",
      ["git", "diff", "--name-only", "--diff-filter=U"] => "mobile/example.dart\n",
    )

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      synchronizer(runner, ready_report).resume
    end

    assert_includes error.message, "unresolved files"
    refute runner.commands.any? { |command| command[0, 2] == ["git", "commit"] }
  end

  def test_resume_commits_only_fully_staged_resolution
    runner = FakeRunner.new(
      ["git", "symbolic-ref", "--quiet", "--short", "HEAD"] => "#{BRANCH}\n",
      ["git", "rev-parse", "--verify", "MERGE_HEAD^{commit}"] => "#{OFFICIAL_SHA}\n",
      ["git", "diff", "--name-only", "--diff-filter=U"] => "",
      ["git", "diff", "--quiet"] => result(status: 0),
      ["git", "diff", "--cached", "--quiet"] => result(status: 1),
      ["git", "diff", "--check"] => "",
      ["git", "diff", "--cached", "--check"] => "",
      ["git", "commit", "--no-edit"] => "Committed\n",
      ["git", "merge-base", "--is-ancestor", OFFICIAL_SHA, "HEAD"] => result(status: 0),
      ["git", "rev-parse", "HEAD"] => "#{MERGE_SHA}\n",
    )

    response = synchronizer(runner, ready_report).resume

    assert_equal :merged, response.status
    assert_equal OFFICIAL_SHA, response.official_sha
    assert_equal MERGE_SHA, response.merge_commit
  end

  private

  def synchronizer(runner, report)
    EnteUpstreamSync::Synchronizer.new(
      runner: runner,
      inspector: FakeInspector.new(report),
      root: Pathname("/tmp/example"),
    )
  end

  def ready_report
    EnteUpstreamSync::CheckReport.new(
      repository_root: "/tmp/example",
      branch: "main",
      base_branch: "main",
      fork_sha: FORK_SHA,
      official_sha: OFFICIAL_SHA,
      merge_base_sha: "e" * 40,
      fork_only_commits: 3,
      upstream_only_commits: 5,
      official_contained: false,
      fetched: false,
      problems: [],
    )
  end

  def result(stdout: "", stderr: "", status:)
    EnteUpstreamSync::CommandResult.new(stdout: stdout, stderr: stderr, status: status)
  end
end
