=begin
Copyright (c) 2011 Solano Labs All Rights Reserved
=end

require "rubygems"
require "thor"
require "highline/import"
require "json"
require "tddium_client"
require File.expand_path("../tddium/constant", __FILE__)

#      Usage:
#
#      tddium suite    # Register the suite for this rails app, or manage its settings
#      tddium spec     # Run the test suite
#      tddium status   # Display information about this suite, and any open dev sessions
#
#      tddium login    # Log your unix user in to a tddium account
#      tddium logout   # Log out
#
#      tddium account  # View/Manage account information
#
#      tddium dev      # Enter "dev" mode, for single-test quick-turnaround debugging.
#      tddium stopdev  # Leave "dev" mode.
#
#      tddium clean    # Clean up test results, especially large objects like videos
#
#      tddium help     # Print this usage message

class Tddium < Thor
  include TddiumConstant

  desc "account", "View/Manage account information"
  method_option :environment, :type => :string, :default => nil
  method_option :email, :type => :string, :default => nil
  method_option :password, :type => :string, :default => nil
  method_option :ssh_key_file, :type => :string, :default => nil
  def account
    set_default_environment(options[:environment])
    if user_logged_in? do |api_response|
        # User is already logged in, so just display the info
        show_user_details(api_response)
      end
    else
      params = get_user_credentials(options.merge(:invited => true))

      # Prompt for the password confirmation if password is not from command line
      unless options[:password]
        password_confirmation = HighLine.ask(Text::Prompt::PASSWORD_CONFIRMATION) { |q| q.echo = "*" }
        unless password_confirmation == params[:password]
          say Text::Process::PASSWORD_CONFIRMATION_INCORRECT
          return
        end
      end

      # Prompt for ssh-key file
      ssh_file = prompt(Text::Prompt::SSH_KEY, options[:ssh_key_file], Default::SSH_FILE)
      params[:user_git_pubkey] = File.open(File.expand_path(ssh_file)) {|file| file.read}

      # Prompt for accepting license
      content =  File.open(File.join(File.dirname(__FILE__), "..", License::FILE_NAME)) do |file|
        file.read
      end
      say content
      license_accepted = ask(Text::Prompt::LICENSE_AGREEMENT)
      return unless license_accepted.downcase == Text::Prompt::Response::AGREE_TO_LICENSE.downcase

      api_result = call_api(:post, Api::Path::USERS, {:user => params}, false, false) do |api_response|
        write_api_key(api_response["user"]["api_key"])
        say Text::Process::ACCOUNT_CREATED % [api_response["user"]["email"], api_response["user"]["recurly_url"]]
      end
      say((api_result.api_status == Api::ErrorCode::INVALID_INVITATION) ? Text::Error::INVALID_INVITATION : api_result.message) unless api_result.success?
    end
  end

  desc "login", "Log in to tddium using your email address and password"
  method_option :environment, :type => :string, :default => nil
  method_option :email, :type => :string, :default => nil
  method_option :password, :type => :string, :default => nil
  def login
    set_default_environment(options[:environment])
    if user_logged_in?
      say Text::Process::ALREADY_LOGGED_IN
    else
      login_user(:params => get_user_credentials(options), :show_error => true) do
        say Text::Process::LOGGED_IN_SUCCESSFULLY
      end
    end
  end

  desc "logout", "Log out of tddium"
  method_option :environment, :type => :string, :default => nil
  def logout
    set_default_environment(options[:environment])
    FileUtils.rm(tddium_file_name) if File.exists?(tddium_file_name)
    say Text::Process::LOGGED_OUT_SUCCESSFULLY
  end

  desc "spec", "Run the test suite"
  method_option :environment, :type => :string, :default => nil
  def spec
    set_default_environment(options[:environment])
    return unless git_repo? && tddium_settings && suite_for_current_branch?

    start_time = Time.now

    # Push the latest code to git
    return unless git_push

    # Call the API to get the suite and its tests
    call_api(:get, current_suite_path) do |api_response|
      test_pattern = api_response["suite"]["test_pattern"]
      test_files = Dir.glob(test_pattern).collect {|file_path| {:test_name => file_path}}

      # Create a session
      call_api(:post, Api::Path::SESSIONS) do |api_response|
        session_id = api_response["session"]["id"]

        # Call the API to register the tests
        call_api(:post, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::REGISTER_TEST_EXECUTIONS}", {:suite_id => current_suite_id, :tests => test_files}) do |api_response|
          # Start the tests
          call_api(:post, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::START_TEST_EXECUTIONS}") do |api_response|
            tests_not_finished_yet = true
            finished_tests = {}
            test_statuses = Hash.new(0)
            api_call_successful = true
            get_test_executions_response = {}

            say Text::Process::STARTING_TEST % test_files.size
            say Text::Process::TERMINATE_INSTRUCTION
            while tests_not_finished_yet && api_call_successful do
              # Poll the API to check the status
              call_api_result = call_api(:get, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::TEST_EXECUTIONS}") do |api_response|
                # Catch Ctrl-C to interrupt the test
                Signal.trap(:INT) do
                  say Text::Process::INTERRUPT
                  say Text::Process::CHECK_TEST_STATUS
                  tests_not_finished_yet = false
                end

                # Print out the progress of running tests
                api_response["tests"].each do |test_name, result_params|
                  test_status = result_params["status"]
                  if result_params["end_time"] && !finished_tests[test_name]
                    message = case test_status
                                when "passed" then [".", :green, false]
                                when "failed" then ["F", :red, false]
                                when "error" then ["E", nil, false]
                                when "pending" then ["*", :yellow, false]
                              end
                    finished_tests[test_name] = test_status
                    test_statuses[test_status] += 1
                    say *message
                  end
                end

                # save response for later use
                get_test_executions_response = api_response

                # If all tests finished, exit the loop else sleep
                if finished_tests.size == api_response["tests"].size
                  tests_not_finished_yet = false
                else
                  sleep(Default::SLEEP_TIME_BETWEEN_POLLS)
                end
              end
              api_call_successful = call_api_result.success?
            end

            # Print out the result
            say Text::Process::FINISHED_TEST % (Time.now - start_time)
            say "#{finished_tests.size} examples, #{test_statuses["failed"]} failures, #{test_statuses["error"]} errors, #{test_statuses["pending"]} pending"
            say Text::Process::CHECK_TEST_REPORT % get_test_executions_response["report"]
          end
        end
      end
    end
  end

  desc "status", "Display information about this suite, and any open dev sessions"
  method_option :environment, :type => :string, :default => nil
  def status
    set_default_environment(options[:environment])
    return unless git_repo? && tddium_settings && suite_for_current_branch?

    call_api(:get, Api::Path::SUITES) do |api_response|
      if api_response["suites"].size == 0
        say Text::Status::NO_SUITE
      else
        say Text::Status::ALL_SUITES % api_response["suites"].collect {|suite| suite["repo_name"]}.join(", ")

        if current_suite = api_response["suites"].detect {|suite| suite["id"] == current_suite_id}
          say Text::Status::SEPARATOR
          say Text::Status::CURRENT_SUITE % current_suite["repo_name"]

          display_attributes(DisplayedAttributes::SUITE, current_suite)

          show_session_details({:active => true}, Text::Status::NO_ACTIVE_SESSION, Text::Status::ACTIVE_SESSIONS)
          show_session_details({:active => false, :order => "date", :limit => 10}, Text::Status::NO_INACTIVE_SESSION, Text::Status::INACTIVE_SESSIONS)
        else
          say Text::Status::CURRENT_SUITE_UNAVAILABLE
        end
      end
    end
  end

  desc "suite", "Register the suite for this project, or manage its settings"
  method_option :test_pattern, :type => :string, :default => nil
  method_option :name, :type => :string, :default => nil
  method_option :environment, :type => :string, :default => nil
  def suite
    set_default_environment(options[:environment])
    return unless git_repo? && tddium_settings

    params = {}
    if current_suite_id
      call_api(:get, current_suite_path) do |api_response|
        # Get the current test pattern and prompt for updates
        params[:test_pattern] = prompt(Text::Prompt::TEST_PATTERN, options[:test_pattern], api_response["suite"]["test_pattern"])

        # Update the current suite if it exists already
        call_api(:put, current_suite_path, {:suite => params}) do |api_response|
          say Text::Process::UPDATE_SUITE
        end
      end
    else
      params[:branch] = current_git_branch
      default_suite_name = File.basename(Dir.pwd)
      params[:repo_name] = options[:name] || default_suite_name

      existing_suite = nil
      use_existing_suite = false
      suite_name_resolved = false
      api_call_successful = true
      while !suite_name_resolved && api_call_successful
        # Check to see if there is an existing suite
        api_call_successful = call_api(:get, Api::Path::SUITES, params) do |api_response|
          existing_suite = api_response["suites"].first

          # Get the suite name
          current_suite_name = params[:repo_name]
          if existing_suite
            # Prompt for using existing suite (unless suite name is passed from command line) or entering new one
            params[:repo_name] = prompt(Text::Prompt::USE_EXISTING_SUITE, options[:name], current_suite_name)
            if options[:name] || params[:repo_name] == Text::Prompt::Response::YES
              # Use the existing suite, so assign the value back and exit the loop
              params[:repo_name] = current_suite_name
              use_existing_suite = true
              suite_name_resolved = true
            end
          elsif current_suite_name == default_suite_name
            # Prompt for using default suite name or entering new one
            params[:repo_name] = prompt(Text::Prompt::SUITE_NAME, options[:name], current_suite_name)
            suite_name_resolved = true if params[:repo_name] == default_suite_name
          else
            # Suite name does not exist yet and already prompted
            suite_name_resolved = true
          end
        end.success?
      end

      if api_call_successful
        if use_existing_suite
          # Write to file and exit when using the existing suite
          write_suite(existing_suite["id"])
          say Text::Status::USING_SUITE % [existing_suite["repo_name"], existing_suite["branch"]]
          return
        end

        params[:ruby_version] = dependency_version(:ruby)
        params[:bundler_version] = dependency_version(:bundle)
        params[:rubygems_version] = dependency_version(:gem)

        params[:test_pattern] = prompt(Text::Prompt::TEST_PATTERN, options[:test_pattern], Default::TEST_PATTERN)

        # Create new suite if it does not exist yet
        call_api(:post, Api::Path::SUITES, {:suite => params}) do |api_response|
          # Save the created suite
          write_suite(api_response["suite"]["id"])

          # Manage git
          `git remote rm #{Git::REMOTE_NAME}`
          `git remote add #{Git::REMOTE_NAME} #{api_response["suite"]["git_repo_uri"]}`
          git_push
        end
      end
    end
  end

  private

  def call_api(method, api_path, params = {}, api_key = nil, show_error = true, &block)
    api_key =  tddium_settings(:fail_with_message => false)["api_key"] if tddium_settings(:fail_with_message => false) && api_key != false
    api_status, http_status, error_message = tddium_client.call_api(method, api_path, params, api_key, &block)
    say error_message if error_message && show_error
    response = Struct.new(:api_status, :http_status, :message) do
      def success?
        self.api_status.to_i.zero?
      end
    end
    response.new(api_status, http_status, error_message)
  end

  def current_git_branch
    @current_git_branch ||= File.basename(`git symbolic-ref HEAD`.gsub("\n", ""))
  end

  def current_suite_id
    tddium_settings["branches"][current_git_branch] if tddium_settings["branches"]
  end

  def current_suite_path
    "#{Api::Path::SUITES}/#{current_suite_id}"
  end

  def dependency_version(command)
    `#{command} -v`.match(Dependency::VERSION_REGEXP)[1]
  end

  def display_attributes(names_to_display, attributes)
    names_to_display.each do |attr|
      say Text::Status::ATTRIBUTE_DETAIL % [attr.gsub("_", " ").capitalize, attributes[attr]] if attributes[attr]
    end
  end

  def environment
    tddium_client.environment
  end

  def get_user(&block)
    call_api(:get, Api::Path::USERS, {}, nil, false, &block)
  end

  def get_user_credentials(options = {})
    params = {}
    # prompt for email/invitation and password
    if options[:invited]
      params[:invitation_token] = options[:invitation_token] || ask(Text::Prompt::INVITATION_TOKEN)
    else
      params[:email] = options[:email] || ask(Text::Prompt::EMAIL)
    end
    params[:password] = options[:password] || HighLine.ask(Text::Prompt::PASSWORD) { |q| q.echo = "*" }
    params
  end

  def git_push
    system("git push #{Git::REMOTE_NAME} #{current_git_branch}")
  end

  def git_repo?
    unless File.exists?(".git")
      message = Text::Error::GIT_NOT_INITIALIZED
      say message
    end
    message.nil?
  end

  def login_user(options = {}, &block)
    # POST (email, password) to /users/sign_in to retrieve an API key
    login_result = call_api(:post, Api::Path::SIGN_IN, {:user => options[:params]}, false, options[:show_error]) do |api_response|
      # On success, write the API key to "~/.tddium.<environment>"
      write_api_key(api_response["api_key"])
      yield api_response if block_given?
    end
    login_result
  end

  def prompt(text, current_value, default_value)
    value = current_value || ask(text % default_value)
    value.empty? ? default_value : value
  end

  def set_default_environment(env)
    if env.nil?
      tddium_client.environment = :development
      tddium_client.environment = :production unless File.exists?(tddium_file_name)
    else
      tddium_client.environment = env.to_sym
    end
  end

  def show_session_details(params, no_session_prompt, all_session_prompt)
    call_api(:get, Api::Path::SESSIONS, params) do |api_response|
      say Text::Status::SEPARATOR
      if api_response["sessions"].size == 0
        say no_session_prompt
      else
        say all_session_prompt
        api_response["sessions"].each do |session|
          session_id = session["id"]
          say Text::Status::SESSION_TITLE % session_id
          call_api(:get, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::TEST_EXECUTIONS}") do |api_response|
            display_attributes(DisplayedAttributes::TEST_EXECUTION, api_response)
          end
        end
      end
    end
  end

  def show_user_details(api_response)
    # Given the user is logged in, she should be able to use "tddium account" to display information about her account:
    # Email address
    # Account creation date
    say api_response["user"]["email"]
    say api_response["user"]["created_at"]
  end

  def suite_for_current_branch?
    unless current_suite_id
      message = Text::Error::NO_SUITE_EXISTS % current_git_branch
      say message
    end
    message.nil?
  end

  def tddium_client
    @tddium_client ||= TddiumClient.new
  end

  def tddium_file_name
    extension = ".#{environment}" unless environment == :production
    ".tddium#{extension}"
  end

  def tddium_settings(options = {})
    options[:fail_with_message] = true unless options[:fail_with_message] == false
    if @tddium_settings.nil? || options[:force_reload]
      if File.exists?(tddium_file_name)
        tddium_config = File.open(tddium_file_name) do |file|
          file.read
        end
        @tddium_settings = JSON.parse(tddium_config) rescue nil
        say (Text::Error::INVALID_TDDIUM_FILE % environment) if @tddium_settings.nil? && options[:fail_with_message]
      else
        say Text::Error::NOT_INITIALIZED if options[:fail_with_message]
      end
    end
    @tddium_settings
  end

  def user_logged_in?(active = true, &block)
    result = tddium_settings(:fail_with_message => false) && tddium_settings["api_key"]
    (result && active) ? get_user(&block).success? : result
  end

  def write_api_key(api_key)
    settings = tddium_settings(:fail_with_message => false) || {}
    File.open(tddium_file_name, "w") do |file|
      file.write(settings.merge({"api_key" => api_key}).to_json)
    end
  end

  def write_suite(suite_id)
    branches = tddium_settings["branches"] || {}
    branches.merge!({current_git_branch => suite_id})
    File.open(tddium_file_name, "w") do |file|
      file.write(tddium_settings.merge({"branches" => branches}).to_json)
    end
  end

end
