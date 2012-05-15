# Copyright (c) 2011, 2012 Solano Labs All Rights Reserved

module Tddium
  class TddiumCli < Thor
    protected

    def set_shell
      if !$stdout.tty? || !$stderr.tty? then
        @shell = Thor::Shell::Basic.new
      end
    end

    def tool_cli_populate(options, params)
      if options[:tool].is_a?(Hash) then
        options[:tool].each_pair do |key, value|
          params[key.to_sym] = value
        end
      end
    end

    def tool_version(tool)
      key = "#{tool}_version".to_sym
      result = @repo_config[key]

      if result
        say Text::Process::CONFIGURED_VERSION % [tool, result]
        return result
      end

      begin
        result = `#{tool} -v`.strip
      rescue Errno::ENOENT
        exit_failure("#{tool} is not on PATH; please install and try again")
      end
      say Text::Process::DEPENDENCY_VERSION % [tool, result]
      result
    end

    def sniff_ruby_version_rvmrc(rvmrc)
      ruby_version = nil
      File.open(rvmrc, 'r') do |file|
        file.each_line do |line|
          line.sub!(/^\s+/, '')
          next unless line =~ /^rvm/
          fields = Shellwords.shellsplit(line)
          fields.each do |field|
            if field =~ /^(ree|1[.][89])/ then
              ruby_version = field.sub(/@.*/, '')
            end
          end
        end
      end
      return ruby_version
    end

    def sniff_ruby_version
      ruby_version = @repo_config[:ruby_version]
      return ruby_version unless ruby_version.nil? || ruby_version.empty?

      git_root = Git.git_root
      if git_root then
        rvmrc = File.join(git_root, '.rvmrc')
        ruby_version = sniff_ruby_version_rvmrc(rvmrc) if File.exists?(rvmrc)
      end
      return ruby_version
    end
   
    def warn(msg='')
      STDERR.puts("WARNING: #{msg}")
    end

    def exit_failure(msg='')
      abort msg
    end

    def display_message(message, prefix=' ---> ')
      color = case message["level"]
                when "error" then :red
                when "warn" then :yellow
                else nil
              end
      print prefix
      say message["text"].rstrip, color
    end

    def display_alerts(messages, level, heading)
      return unless messages
      interest = messages.select{|m| [level].include?(m['level'])}
      if interest.size > 0
        say heading
        interest.each do |m|
          display_message(m, '')
        end
      end
    end
  end
end
