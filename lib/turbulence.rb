require 'flog'
require 'stringio'
require 'turbulence/scatter_plot_generator'
require 'turbulence/command_line_interface'

class Turbulence
  class Reporter < StringIO
    def average
      Float(string.scan(/^\s+([^:]+).*total$/).flatten.first)
    end
  end

  attr_reader :dir
  attr_reader :metrics
  def initialize(dir)
    @dir = dir
    @metrics = {}
    Dir.chdir(dir) do
      churn
      complexity
    end
  end

  def ruby_files
    files = ["app/models", "app/controllers", "app/helpers", "lib"].map{|base_dir| "#{base_dir}/**/*\.rb"}
    @ruby_files ||= Dir[*files]
  end

  def churn
    files = changes_by_ruby_file.select { |_, filename| ruby_files.include?(filename) }
    files.each do |count, filename|
      print "."
      metrics_for(filename)[:churn] = Integer(count)
    end
  end

  def complexity
    flogger = Flog.new
    ruby_files.each do |filename|
      print "."

      begin
        flogger.flog filename
        reporter = Reporter.new
        flogger.report(reporter)
        metrics_for(filename)[:complexity] = reporter.average
      rescue SyntaxError, Racc::ParseError => e
        puts "\nError flogging: #{filename}\n"
      end
    end
  end

  def metrics_for(filename)
    @metrics[filename] ||= {}
  end

  private
    def changes_by_ruby_file
      ruby_files_changed_in_git.group_by(&:first).map do |filename, stats|
        [stats.map(&:last).tap{|list| list.pop}.inject(0){|n, i| n + i}, filename]
      end
    end

    def ruby_files_changed_in_git
      git_log_command.each_line.reject{|line| line =~ /^\n$/}.map do |line|
        adds, deletes, filename = line.chomp.split(/\t/)
        [filename, adds.to_i + deletes.to_i]
      end.select do |count, filename|
        filename =~ /\.rb$/ && File.exist?(filename)
      end
    end

    def git_log_command
      `git log --all -M -C --numstat --format="%n"`
    end
end
