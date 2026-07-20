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

  def execute(*argv, chdir:, env:, output:)
    response = capture(*argv, chdir: chdir.to_s, env: env)
    raise EnteUpstreamSync::CommandFailure.new(argv, response) unless response.success?

    output.write(response.stdout)
    response
  end

  private

  def result(stdout, stderr: "", status: 0)
    EnteUpstreamSync::CommandResult.new(stdout: stdout, stderr: stderr, status: status)
  end
end

class PermissiveValidationRunner
  attr_reader :commands

  def initialize(statuses: [""])
    @commands = []
    @statuses = statuses.dup
  end

  def run(*argv, **options)
    @commands << [:run, argv, options]
    case argv
    when ["git", "symbolic-ref", "--quiet", "--short", "HEAD"]
      "sync/upstream-2026-07-20-bbbbbbbbbb"
    when ["git", "status", "--porcelain", "--untracked-files=all"]
      @statuses.length > 1 ? @statuses.shift : @statuses.first
    when ["git", "log", "--first-parent", "--merges", "-n", "50", "--format=%H%x09%P%x09%s"]
      "#{"d" * 40}\t#{"a" * 40} #{"b" * 40}\tMerge official Ente main at #{"b" * 40}\n"
    when ["git", "ls-files", "-z", "*.dart"]
      "mobile/a.dart\0mobile/b.dart\0"
    when ["git", "rev-parse", "HEAD"]
      "c" * 40
    else
      ""
    end
  end

  def capture(*argv, **options)
    @commands << [:capture, argv, options]
    status = argv == ["git", "rev-parse", "--verify", "MERGE_HEAD"] ? 1 : 0
    EnteUpstreamSync::CommandResult.new(stdout: "", stderr: "", status: status)
  end

  def execute(*argv, **options)
    @commands << [:execute, argv, options]
    EnteUpstreamSync::CommandResult.new(stdout: "", stderr: "", status: 0)
  end
end

class PublishingRunner
  BRANCH = "sync/upstream-2026-07-20-#{"b" * 10}"
  COMMIT = "c" * 40
  MERGE_COMMIT = "d" * 40
  FORK_SHA = "a" * 40
  OFFICIAL_SHA = "b" * 40

  attr_reader :commands, :created_body

  def initialize(remote_sha: nil, remote_shas: nil, pull_requests: [], issues: [])
    @remote_sha = remote_sha
    @remote_shas = remote_shas&.dup
    @pull_requests = pull_requests
    @issues = issues
    @commands = []
    @created_body = nil
  end

  def run(*argv, **options)
    @commands << [:run, argv, options]
    case argv
    when ["git", "symbolic-ref", "--quiet", "--short", "HEAD"]
      BRANCH
    when ["git", "status", "--porcelain", "--untracked-files=all"]
      ""
    when ["git", "rev-parse", "HEAD"]
      COMMIT
    when ["git", "log", "--first-parent", "--merges", "-n", "50", "--format=%H%x09%P%x09%s"]
      "#{MERGE_COMMIT}\t#{FORK_SHA} #{OFFICIAL_SHA}\tMerge official Ente main at #{OFFICIAL_SHA}\n"
    when ["git", "remote", "get-url", "--all", "origin"]
      "https://github.com/vanton1/ente.git\n"
    when ["git", "remote", "get-url", "--all", "--push", "origin"]
      "https://github.com/vanton1/ente.git\n"
    when ["git", "remote", "get-url", "--all", "upstream"]
      "https://github.com/ente/ente.git\n"
    when ["git", "remote", "get-url", "--all", "--push", "upstream"]
      "DISABLED\n"
    when ["git", "fetch", "origin", "main", "--prune"],
         ["git", "fetch", "origin", BRANCH],
         ["git", "branch", "--set-upstream-to=origin/#{BRANCH}", BRANCH],
         ["/usr/bin/gh", "auth", "status", "--hostname", "github.com"]
      ""
    when ["git", "rev-parse", "--verify", "origin/main^{commit}"]
      FORK_SHA
    when ["git", "ls-remote", "--heads", "origin", "refs/heads/#{BRANCH}"]
      sha = if @remote_shas
              @remote_shas.length > 1 ? @remote_shas.shift : @remote_shas.first
            else
              @remote_sha
            end
      sha ? "#{sha}\trefs/heads/#{BRANCH}\n" : ""
    when ["/usr/bin/gh", "pr", "list", "--repo", "vanton1/ente", "--head", BRANCH, "--state", "all", "--json", "number,state,url,headRefOid"]
      JSON.generate(@pull_requests)
    when ["/usr/bin/gh", "issue", "list", "--repo", "vanton1/ente", "--state", "open", "--limit", "100", "--json", "number,title,body,url,state"]
      JSON.generate(@issues)
    else
      if argv[0, 3] == ["/usr/bin/gh", "pr", "create"]
        @created_body = argv[argv.index("--body") + 1]
        "https://github.com/vanton1/ente/pull/99\n"
      else
        raise "Unexpected command: #{argv.inspect}"
      end
    end
  end

  def capture(*argv, **options)
    @commands << [:capture, argv, options]
    status = argv == ["git", "rev-parse", "--verify", "MERGE_HEAD"] ? 1 : 0
    EnteUpstreamSync::CommandResult.new(stdout: "", stderr: "", status: status)
  end

  def execute(*argv, **options)
    @commands << [:execute, argv, options]
    expected = [
      "/usr/bin/git",
      "push",
      "git@github.com:vanton1/ente.git",
      "HEAD:refs/heads/#{BRANCH}",
    ]
    raise "Unexpected streaming command: #{argv.inspect}" unless argv == expected

    @remote_sha = COMMIT
    @remote_shas = nil
    options.fetch(:output).puts("uploaded")
    EnteUpstreamSync::CommandResult.new(stdout: "uploaded\n", stderr: "", status: 0)
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

  def test_no_change_returns_without_creating_a_branch
    report = ready_report
    report.upstream_only_commits = 0
    report.official_contained = true
    runner = FakeRunner.new({})

    response = synchronizer(runner, report).start(fetch: false)

    assert_equal :already_synchronized, response.status
    assert_equal OFFICIAL_SHA, response.official_sha
    assert_empty runner.commands
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

class IntegrationStateTest < Minitest::Test
  def test_finds_verified_merge_below_repair_commits
    official = "b" * 40
    runner = FakeRunner.new(
      ["git", "log", "--first-parent", "--merges", "-n", "50", "--format=%H%x09%P%x09%s"] =>
        "#{"d" * 40}\t#{"a" * 40} #{official}\tMerge official Ente main at #{official}\n",
    )

    state = EnteUpstreamSync::IntegrationState.current(runner)

    assert_equal official, state.official_sha
    assert_equal "a" * 40, state.fork_parent
  end

  def test_rejects_message_whose_sha_is_not_the_second_parent
    runner = FakeRunner.new(
      ["git", "log", "--first-parent", "--merges", "-n", "50", "--format=%H%x09%P%x09%s"] =>
        "#{"d" * 40}\t#{"a" * 40} #{"e" * 40}\tMerge official Ente main at #{"b" * 40}\n",
    )

    assert_raises(EnteUpstreamSync::SafetyFailure) do
      EnteUpstreamSync::IntegrationState.current(runner)
    end
  end
end

class PublisherTest < Minitest::Test
  TOOLS = { git: "/usr/bin/git", gh: "/usr/bin/gh" }.freeze
  ISSUE = {
    "number" => 42,
    "title" => "Official Ente is ahead",
    "body" => "#{EnteUpstreamSync::UpstreamIssue::MARKER}\nDrift detected.",
    "url" => "https://github.com/vanton1/ente/issues/42",
    "state" => "OPEN",
  }.freeze

  def test_confirmation_mismatch_performs_no_external_mutation
    runner = PublishingRunner.new(issues: [ISSUE])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      publisher(runner, "no\n").publish(validation: validation)
    end

    assert_includes error.message, "Nothing was pushed"
    refute runner.commands.any? { |kind, argv, _options| kind == :execute || argv[0, 3] == ["/usr/bin/gh", "pr", "create"] }
  end

  def test_pushes_only_to_canonical_fork_ssh_url_and_creates_linked_pr
    runner = PublishingRunner.new(issues: [ISSUE])

    result = publisher(runner, "PUSH #{PublishingRunner::BRANCH}\n").publish(validation: validation)

    assert_equal :published, result.status
    assert_equal 99, result.pull_request_number
    assert_equal 42, result.issue_number
    assert_includes runner.created_body, "Closes #42"
    assert_includes runner.created_body, PublishingRunner::OFFICIAL_SHA
    pushes = runner.commands.select { |kind, _argv, _options| kind == :execute }
    assert_equal 1, pushes.length
    assert_equal "git@github.com:vanton1/ente.git", pushes.first[1][2]
  end

  def test_reuses_matching_remote_branch_without_uploading_again
    runner = PublishingRunner.new(remote_sha: PublishingRunner::COMMIT, issues: [ISSUE])

    result = publisher(runner, "PUSH #{PublishingRunner::BRANCH}\n").publish(validation: validation)

    assert_equal :pull_request_created, result.status
    refute runner.commands.any? { |kind, _argv, _options| kind == :execute }
    assert runner.created_body
  end

  def test_mismatched_remote_branch_stops_before_confirmation
    runner = PublishingRunner.new(remote_sha: "e" * 40, issues: [ISSUE])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      publisher(runner, "PUSH #{PublishingRunner::BRANCH}\n").publish(validation: validation)
    end

    assert_includes error.message, "not validated commit"
    refute runner.commands.any? { |kind, _argv, _options| kind == :execute }
  end

  def test_remote_change_during_confirmation_is_detected_before_push
    runner = PublishingRunner.new(remote_shas: [nil, "e" * 40], issues: [ISSUE])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      publisher(runner, "PUSH #{PublishingRunner::BRANCH}\n").publish(validation: validation)
    end

    assert_includes error.message, "not validated commit"
    refute runner.commands.any? { |kind, _argv, _options| kind == :execute }
  end

  def test_existing_matching_pull_request_is_reused_without_confirmation
    pull_request = {
      "number" => 88,
      "state" => "OPEN",
      "url" => "https://github.com/vanton1/ente/pull/88",
      "headRefOid" => PublishingRunner::COMMIT,
    }
    runner = PublishingRunner.new(
      remote_sha: PublishingRunner::COMMIT,
      pull_requests: [pull_request],
      issues: [ISSUE],
    )

    result = publisher(runner, "").publish(validation: validation)

    assert_equal :existing_pull_request, result.status
    assert_equal 88, result.pull_request_number
    refute runner.commands.any? { |kind, argv, _options| kind == :execute || argv[0, 3] == ["/usr/bin/gh", "pr", "create"] }
  end

  def test_duplicate_marker_issues_stop_closed
    second = ISSUE.merge("number" => 43, "url" => "https://github.com/vanton1/ente/issues/43")
    runner = PublishingRunner.new(issues: [ISSUE, second])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      publisher(runner, "PUSH #{PublishingRunner::BRANCH}\n").publish(validation: validation)
    end

    assert_includes error.message, "Multiple open"
  end

  private

  def publisher(runner, input)
    EnteUpstreamSync::Publisher.new(
      runner: runner,
      root: "/repo",
      tools: TOOLS,
      input: StringIO.new(input),
      output: StringIO.new,
    )
  end

  def validation
    EnteUpstreamSync::ValidationResult.new(
      branch: PublishingRunner::BRANCH,
      commit: PublishingRunner::COMMIT,
      official_sha: PublishingRunner::OFFICIAL_SHA,
      with_builds: false,
      steps: ["tests", "analysis"],
    )
  end
end

class ValidatorTest < Minitest::Test
  TOOLS = {
    git: "/usr/bin/git",
    gh: "/usr/bin/gh",
    flutter: "/tool/flutter",
    dart: "/tool/dart",
    cargo: "/tool/cargo",
    pod: "/tool/pod",
  }.freeze

  def test_runs_complete_default_gate_without_platform_builds
    runner = PermissiveValidationRunner.new
    output = StringIO.new

    result = EnteUpstreamSync::Validator.new(
      runner: runner,
      root: "/repo",
      tools: TOOLS,
      output: output,
    ).validate(with_builds: false)

    assert_equal 10, result.steps.length
    refute result.with_builds
    assert runner.commands.any? { |kind, argv, _options| kind == :execute && argv.include?("--enforce-lockfile") }
    assert runner.commands.any? { |kind, argv, _options| kind == :execute && argv.include?("--dart-define=configurableEndpoint=true") }
    assert runner.commands.any? { |kind, argv, _options| kind == :execute && argv.include?("--dart-define=lockedEndpoint=true") }
    refute runner.commands.any? { |kind, argv, _options| kind == :execute && argv.include?("build_self_hosted_android.sh") }
  end

  def test_with_builds_uses_guarded_wrappers_and_public_endpoint
    runner = PermissiveValidationRunner.new
    result = EnteUpstreamSync::Validator.new(
      runner: runner,
      root: "/repo",
      tools: TOOLS.merge(java: "/tool/java", xcodebuild: "/tool/xcodebuild"),
      output: StringIO.new,
    ).validate(with_builds: true)

    assert result.with_builds
    build_commands = runner.commands.select do |kind, argv, _options|
      kind == :execute && argv.first.include?("build_self_hosted_")
    end
    assert_equal 2, build_commands.length
    build_commands.each do |_kind, _argv, options|
      assert_equal EnteUpstreamSync::Validator::PUBLIC_ENDPOINT, options[:env]["ENTE_SELF_HOSTED_ENDPOINT"]
    end
  end

  def test_source_drift_stops_before_dependency_commands_continue
    runner = PermissiveValidationRunner.new(statuses: ["", " M generated.dart\n"])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      EnteUpstreamSync::Validator.new(
        runner: runner,
        root: "/repo",
        tools: TOOLS,
        output: StringIO.new,
      ).validate(with_builds: false)
    end

    assert_includes error.message, "source drift"
    refute runner.commands.any? { |kind, argv, _options| kind == :execute && argv.include?("--enforce-lockfile") }
  end

  def test_generated_source_drift_stops_before_second_generation
    runner = PermissiveValidationRunner.new(statuses: ["", "", "", " M generated.dart\n"])

    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      EnteUpstreamSync::Validator.new(
        runner: runner,
        root: "/repo",
        tools: TOOLS,
        output: StringIO.new,
      ).validate(with_builds: false)
    end

    assert_includes error.message, "after first Rust binding generation"
    generations = runner.commands.count do |kind, argv, _options|
      kind == :execute && argv == ["/tool/cargo", "codegen", "frb"]
    end
    assert_equal 1, generations
  end
end

class ToolResolverTest < Minitest::Test
  def test_missing_toolchain_stops_with_complete_diagnostic
    error = assert_raises(EnteUpstreamSync::SafetyFailure) do
      EnteUpstreamSync::ToolResolver.new(env: { "PATH" => "", "HOME" => "/missing" }).resolve(
        with_builds: true,
        with_github: true,
      )
    end

    assert_includes error.message, "Required tools are unavailable"
    assert_includes error.message, "git"
    assert_includes error.message, "gh"
    assert_includes error.message, "xcodebuild"
  end
end
