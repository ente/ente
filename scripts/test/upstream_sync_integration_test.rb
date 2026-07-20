# frozen_string_literal: true

require "fileutils"
require "minitest/autorun"
require "tmpdir"
require_relative "../lib/upstream_sync"

class IntegrationInspector
  def initialize(report)
    @report = report
  end

  def check(fetch:)
    @report
  end
end

class UpstreamSyncGitIntegrationTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("ente-upstream-sync-")
    @runner = EnteUpstreamSync::Runner.new(root: @directory)
    git("init")
    git("branch", "-M", "main")
    git("config", "user.name", "Upstream Sync Test")
    git("config", "user.email", "upstream-sync@example.invalid")
    write("shared.txt", "base\n")
    git("add", "shared.txt")
    git("commit", "-m", "base")
    @base_sha = git("rev-parse", "HEAD")
  end

  def teardown
    FileUtils.remove_entry(@directory) if @directory && File.exist?(@directory)
  end

  def test_clean_real_merge_contains_exact_official_commit
    report = divergent_report(conflict: false)

    result = synchronizer(report).start(
      fetch: false,
      expected_official_sha: report.official_sha,
      date: Date.new(2026, 7, 20),
    )

    assert_equal :merged, result.status
    assert_equal "sync/upstream-2026-07-20-#{report.official_sha[0, 10]}", result.branch
    assert @runner.capture("git", "merge-base", "--is-ancestor", report.official_sha, "HEAD").success?
    assert_equal 2, git("show", "-s", "--format=%P", result.merge_commit).split.length
  end

  def test_real_conflict_is_preserved_for_manual_repair
    report = divergent_report(conflict: true)

    error = assert_raises(EnteUpstreamSync::MergeStopped) do
      synchronizer(report).start(fetch: false, date: Date.new(2026, 7, 20))
    end

    assert_equal ["shared.txt"], error.conflicts
    assert_equal error.branch, git("branch", "--show-current")
    assert @runner.capture("git", "rev-parse", "--verify", "MERGE_HEAD").success?
    assert_includes File.read(File.join(@directory, "shared.txt")), "<<<<<<<"
  end

  def test_resume_accepts_reviewed_repair_commit_above_verified_merge
    report = divergent_report(conflict: false)
    synchronizer(report).start(fetch: false, date: Date.new(2026, 7, 20))
    write("repair.txt", "reviewed repair\n")
    git("add", "repair.txt")
    git("commit", "-m", "Repair self-hosted integration")
    repair_sha = git("rev-parse", "HEAD")

    result = synchronizer(report).resume

    assert_equal :ready_for_validation, result.status
    assert_equal report.official_sha, result.official_sha
    assert_equal repair_sha, result.merge_commit
  end

  private

  def divergent_report(conflict:)
    if conflict
      write("shared.txt", "fork\n")
      git("add", "shared.txt")
    else
      write("fork.txt", "fork\n")
      git("add", "fork.txt")
    end
    git("commit", "-m", "fork work")
    fork_sha = git("rev-parse", "HEAD")

    git("switch", "-c", "official", @base_sha)
    if conflict
      write("shared.txt", "official\n")
      git("add", "shared.txt")
    else
      write("official.txt", "official\n")
      git("add", "official.txt")
    end
    git("commit", "-m", "official work")
    official_sha = git("rev-parse", "HEAD")
    git("switch", "main")

    EnteUpstreamSync::CheckReport.new(
      repository_root: @directory,
      branch: "main",
      base_branch: "main",
      fork_sha: fork_sha,
      official_sha: official_sha,
      merge_base_sha: @base_sha,
      fork_only_commits: 1,
      upstream_only_commits: 1,
      official_contained: false,
      fetched: false,
      problems: [],
    )
  end

  def synchronizer(report)
    EnteUpstreamSync::Synchronizer.new(
      runner: @runner,
      inspector: IntegrationInspector.new(report),
      root: @directory,
    )
  end

  def git(*arguments)
    @runner.run("git", *arguments)
  end

  def write(relative_path, contents)
    File.write(File.join(@directory, relative_path), contents)
  end
end
