#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "optparse"
require "open3"
require "pathname"
require_relative "lib/upstream_sync"

module EnteUpstreamSync
  class HelpRequested < StandardError; end

  class CLI
    def initialize(argv:, stdout: $stdout, stderr: $stderr, cwd: Dir.pwd)
      @argv = argv.dup
      @stdout = stdout
      @stderr = stderr
      @cwd = cwd
    end

    def run
      command = @argv.shift
      return usage("Missing command.") unless command
      return print_help if %w[-h --help help].include?(command)
      case command
      when "check"
        run_check
      when "start"
        run_start
      when "resume"
        run_resume
      else
        usage("Unknown command: #{command}")
      end
    rescue OptionParser::ParseError => error
      usage(error.message)
    rescue HelpRequested => help
      @stdout.puts(help.message)
      0
    rescue NotReady => error
      @stderr.puts(TextReport.render(error.report))
      EXIT_NOT_READY
    rescue MergeStopped => error
      print_merge_stopped(error)
      EXIT_NOT_READY
    rescue SafetyFailure => error
      @stderr.puts("Stopped safely: #{error.message}")
      EXIT_NOT_READY
    rescue CommandFailure => error
      @stderr.puts(error.message)
      EXIT_COMMAND_FAILED
    end

    private

    def run_check
      options = common_options(@argv, json: true)
      root, runner, inspector = components(options)
      report = inspector.check(fetch: options[:fetch])

      if options[:json]
        @stdout.puts(JSON.pretty_generate(report.to_h))
      else
        @stdout.puts(TextReport.render(report))
      end
      report.ready? ? 0 : EXIT_NOT_READY
    end

    def run_start
      options = common_options(@argv, start: true)
      root, runner, inspector = components(options)
      result = Synchronizer.new(runner: runner, inspector: inspector, root: root).start(
        fetch: options[:fetch],
        expected_official_sha: options[:official_sha],
        date: options[:date],
      )
      if result.status == :already_synchronized
        @stdout.puts("Fork main already contains official #{result.official_sha}.")
      else
        print_merge_success(result)
      end
      0
    end

    def run_resume
      raise OptionParser::InvalidArgument, "Unexpected arguments: #{@argv.join(" ")}" unless @argv.empty?

      root = repository_root
      runner = Runner.new(root: root)
      inspector = Inspector.new(runner: runner, root: root)
      result = Synchronizer.new(runner: runner, inspector: inspector, root: root).resume
      print_merge_success(result)
      0
    end

    def common_options(argv, json: false, start: false)
      options = {
        fetch: true,
        json: false,
        origin: Inspector::DEFAULT_ORIGIN,
        upstream: Inspector::DEFAULT_UPSTREAM,
        base_branch: Inspector::DEFAULT_BASE_BRANCH,
        fork_repository: Inspector::DEFAULT_FORK_REPOSITORY,
        official_repository: Inspector::DEFAULT_OFFICIAL_REPOSITORY,
      }
      options[:official_sha] = nil if start
      options[:date] = Date.today if start
      parser = OptionParser.new do |value|
        command = start ? "start" : "check"
        value.banner = "Usage: ./scripts/sync_upstream.sh #{command} [options]"
        value.on("--[no-]fetch", "Fetch origin and upstream main (default: fetch)") { |setting| options[:fetch] = setting }
        value.on("--json", "Print a stable JSON readiness report") { options[:json] = true } if json
        value.on("--base BRANCH", "Fork base branch (default: main)") { |setting| options[:base_branch] = setting }
        value.on("--origin REMOTE", "Fork remote (default: origin)") { |setting| options[:origin] = setting }
        value.on("--upstream REMOTE", "Official remote (default: upstream)") { |setting| options[:upstream] = setting }
        value.on("--fork REPOSITORY", "Expected fork owner/repository") { |setting| options[:fork_repository] = setting }
        value.on("--official REPOSITORY", "Expected official owner/repository") { |setting| options[:official_repository] = setting }
        if start
          value.on("--official-sha SHA", /\A[0-9a-f]{40}\z/, "Require the fetched official branch to equal SHA") do |setting|
            options[:official_sha] = setting
          end
          value.on("--date YYYY-MM-DD", "Override branch date (deterministic testing)") do |setting|
            options[:date] = Date.iso8601(setting)
          rescue Date::Error
            raise OptionParser::InvalidArgument, "date must use YYYY-MM-DD"
          end
        end
        value.on("-h", "--help", "Show this help") do
          raise HelpRequested, value.to_s
        end
      end
      parser.parse!(argv)
      raise OptionParser::InvalidArgument, "Unexpected arguments: #{argv.join(" ")}" unless argv.empty?

      options
    end

    def components(options)
      root = repository_root
      runner = Runner.new(root: root)
      inspector = Inspector.new(
        runner: runner,
        root: root,
        origin: options[:origin],
        upstream: options[:upstream],
        base_branch: options[:base_branch],
        fork_repository: options[:fork_repository],
        official_repository: options[:official_repository],
      )
      [root, runner, inspector]
    end

    def repository_root
      stdout, stderr, status = Open3.capture3(
        "git",
        "rev-parse",
        "--show-toplevel",
        chdir: @cwd,
      )
      unless status.success?
        raise CommandFailure.new(
          ["git", "rev-parse", "--show-toplevel"],
          CommandResult.new(stdout: stdout, stderr: stderr, status: status.exitstatus),
        )
      end
      Pathname(stdout.strip).expand_path
    end

    def print_help
      @stdout.puts(<<~HELP)
        Guarded local synchronization of the Ente fork with official upstream.

        Usage:
          ./scripts/sync_upstream.sh check [options]
          ./scripts/sync_upstream.sh start [options]
          ./scripts/sync_upstream.sh resume

        Commands:
          check   Fetch and report exact upstream drift and local readiness
          start   Create a dated integration branch and merge the exact official SHA
          resume  Finish or verify a preserved integration merge after manual repair

        Run a command with --help for its options. Conflicts and failed safety
        checks preserve the integration branch and never modify fork main.
      HELP
      0
    end

    def usage(message)
      @stderr.puts(message)
      @stderr.puts("Run './scripts/sync_upstream.sh --help' for usage.")
      EXIT_USAGE
    end

    def print_merge_success(result)
      @stdout.puts("Upstream merge ready for validation.")
      @stdout.puts("Branch: #{result.branch}")
      @stdout.puts("Official SHA: #{result.official_sha}")
      @stdout.puts("Merge commit: #{result.merge_commit}")
      @stdout.puts("Next: ./scripts/sync_upstream.sh validate")
    end

    def print_merge_stopped(error)
      detail = error.result.stderr.strip
      detail = error.result.stdout.strip if detail.empty?
      @stderr.puts("Merge stopped safely on #{error.branch}.")
      @stderr.puts(detail) unless detail.empty?
      unless error.conflicts.empty?
        @stderr.puts("Unresolved files:")
        error.conflicts.each { |file| @stderr.puts("- #{file}") }
      end
      @stderr.puts("Resolve and stage every conflict, then run:")
      @stderr.puts("  ./scripts/sync_upstream.sh resume")
      @stderr.puts("To abandon only after inspection, run:")
      @stderr.puts("  git merge --abort")
    end
  end
end

exit EnteUpstreamSync::CLI.new(argv: ARGV).run if $PROGRAM_NAME == __FILE__
