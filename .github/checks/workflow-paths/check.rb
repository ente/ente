require "yaml"

Dir.chdir(ARGV.fetch(0, "."))
failed = false

Dir[".github/workflows/*.{yml,yaml}"].sort.each do |path|
  workflow = YAML.safe_load(File.read(path), aliases: true)
  events = workflow["on"] || workflow[true]
  next unless events.is_a?(Hash)

  events.each do |event, config|
    next unless config.is_a?(Hash)

    %w[paths paths-ignore].each do |key|
      patterns = config[key]
      next unless patterns.is_a?(Array)
      next if patterns.any? { |pattern| pattern.start_with?("!") }
      next if patterns == patterns.sort

      warn "#{path}: on.#{event}.#{key} must be sorted"
      failed = true
    end
  end
end

exit(failed ? 1 : 0)
