=begin
Copyright (c) 2011 Solano Labs All Rights Reserved
=end

require "rubygems"
require "thor"
require "highline/import"
require "json"
require "tddium_client"
require "base64"
require "erb"
require File.expand_path("../tddium/constant", __FILE__)
require File.expand_path("../tddium/version", __FILE__)
require File.expand_path("../tddium/heroku", __FILE__)

#      Usage:
#      tddium suite    # Register the suite for this rails app, or manage its settings
#      tddium spec     # Run the test suite
#      tddium status   # Display information about this suite, and any open dev sessions
#
#      tddium login    # Log your unix user in to a tddium account
#      tddium logout   # Log out
#
#      tddium account  # View/Manage account information
#      tddium password # Change password
#
#      tddium help     # Print this usage message

class TddiumError < Exception
  attr_reader :message

  def initialize(message)
    @message = message
  end
end

class Tddium < Thor
  include TddiumConstant
  
  class_option :environment, :type => :string, :default => nil
  class_option :port, :type => :numeric, :default => nil

  desc "account", "View/Manage account information"
  method_option :email, :type => :string, :default => nil
  method_option :password, :type => :string, :default => nil
  method_option :ssh_key_file, :type => :string, :default => nil
  def account
    set_shell
    set_default_environment
    if user_details = user_logged_in?
      # User is already logged in, so just display the info
      show_user_details(user_details)
    else
      params = get_user_credentials(options.merge(:invited => true))

      # Prompt for the password confirmation if password is not from command line
      unless options[:password]
        password_confirmation = HighLine.ask(Text::Prompt::PASSWORD_CONFIRMATION) { |q| q.echo = "*" }
        unless password_confirmation == params[:password]
          exit_failure Text::Process::PASSWORD_CONFIRMATION_INCORRECT
        end
      end

      begin
        params[:user_git_pubkey] = prompt_ssh_key(options[:ssh_key_file])
      rescue TddiumError => e
        exit_failure e.message
      end

      # Prompt for accepting license
      content =  File.open(File.join(File.dirname(__FILE__), "..", License::FILE_NAME)) do |file|
        file.read
      end
      say content
      license_accepted = ask(Text::Prompt::LICENSE_AGREEMENT)
      return unless license_accepted.downcase == Text::Prompt::Response::AGREE_TO_LICENSE.downcase

      begin
        say Text::Process::STARTING_ACCOUNT_CREATION
        new_user = call_api(:post, Api::Path::USERS, {:user => params}, false, false)
        write_api_key(new_user["user"]["api_key"])
        role = new_user["user"]["account_role"]
        if role.nil? || role == "owner"
          say Text::Process::ACCOUNT_CREATED % [new_user["user"]["email"], new_user["user"]["recurly_url"]]
        else
          say Text::Process::ACCOUNT_ADDED % [new_user["user"]["email"], new_user["user"]["account_role"], new_user["user"]["account"]]
        end
      rescue TddiumClient::Error::API => e
        say((e.status == Api::ErrorCode::INVALID_INVITATION) ? Text::Error::INVALID_INVITATION : e.message)
      rescue TddiumClient::Error::Base => e
        say e.message
      end
    end
  end

  desc "account:add [ROLE] [EMAIL]", "Authorize and invite a user to use your account"
  define_method "account:add" do |role, email|
    set_shell
    set_default_environment
    user_details = user_logged_in?(true, true)
    exit_failure unless user_details

    params = {:role=>role, :email=>email}
    begin
      say Text::Process::ADDING_MEMBER % [params[:email], params[:role]]
      result = call_api(:post, Api::Path::MEMBERSHIPS, params)
      say Text::Process::ADDED_MEMBER % email
    rescue TddiumClient::Error::API => e
      exit_failure Text::Error::ADD_MEMBER_ERROR % [email, e.message]
    end
  end

  desc "account:remove [EMAIL]", "Remove a user from your account"
  define_method "account:remove" do |email|
    set_shell
    set_default_environment
    user_details = user_logged_in?(true, true)
    exit_failure unless user_details

    begin
      say Text::Process::REMOVING_MEMBER % email
      result = call_api(:delete, "#{Api::Path::MEMBERSHIPS}/#{email}")
      say Text::Process::REMOVED_MEMBER % email
    rescue TddiumClient::Error::API => e
      exit_failure Text::Error::REMOVE_MEMBER_ERROR % [email, e.message]
    end
  end

  desc "heroku", "Connect Heroku account with Tddium"
  method_option :email, :type => :string, :default => nil
  method_option :password, :type => :string, :default => nil
  method_option :ssh_key_file, :type => :string, :default => nil
  method_option :app, :type => :string, :default => nil
  def heroku
    set_shell
    set_default_environment
    if user_details = user_logged_in?
      # User is already logged in, so just display the info
      show_user_details(user_details)
    else
      begin
        heroku_config = HerokuConfig.read_config(options[:app])
        # User has logged in to heroku, and TDDIUM environment variables are
        # present
        handle_heroku_user(options, heroku_config)
      rescue HerokuConfig::HerokuNotFound
        gemlist = `gem list heroku`
        msg = Text::Error::Heroku::NOT_FOUND % gemlist
        exit_failure msg
      rescue HerokuConfig::TddiumNotAdded
        exit_failure Text::Error::Heroku::NOT_ADDED
      rescue HerokuConfig::InvalidFormat
        exit_failure Text::Error::Heroku::INVALID_FORMAT
      rescue HerokuConfig::NotLoggedIn
        exit_failure Text::Error::Heroku::NOT_LOGGED_IN
      rescue HerokuConfig::AppNotFound
        exit_failure Text::Error::Heroku::APP_NOT_FOUND % options[:app]
      end
    end
  end

  desc "password", "Change password"
  map "passwd" => :password
  def password
    set_shell
    set_default_environment
    return unless tddium_settings
    user_details = user_logged_in?
    return unless user_details
    
    params = {}
    params[:current_password] = HighLine.ask(Text::Prompt::CURRENT_PASSWORD) { |q| q.echo = "*" }
    params[:password] = HighLine.ask(Text::Prompt::NEW_PASSWORD) { |q| q.echo = "*" }
    params[:password_confirmation] = HighLine.ask(Text::Prompt::PASSWORD_CONFIRMATION) { |q| q.echo = "*" }

    begin
      user_id = user_details["user"]["id"]
      result = call_api(:put, "#{Api::Path::USERS}/#{user_id}/", {:user=>params},
                        tddium_settings["api_key"], false)
      say Text::Process::PASSWORD_CHANGED
    rescue TddiumClient::Error::API => e
      say Text::Error::PASSWORD_ERROR % e.explanation
    rescue TddiumClient::Error::Base => e
      say e.message
    end
  end

  desc "login", "Log in to tddium using your email address and password"
  method_option :email, :type => :string, :default => nil
  method_option :password, :type => :string, :default => nil
  def login
    set_shell
    set_default_environment
    if user_logged_in?
      say Text::Process::ALREADY_LOGGED_IN
    elsif login_user(:params => get_user_credentials(options), :show_error => true)
      say Text::Process::LOGGED_IN_SUCCESSFULLY 
    else
      exit_failure
    end
  end

  desc "logout", "Log out of tddium"
  def logout
    set_shell
    set_default_environment
    FileUtils.rm(tddium_file_name) if File.exists?(tddium_file_name)
    say Text::Process::LOGGED_OUT_SUCCESSFULLY
  end

  desc "spec", "Run the test suite"
  method_option :user_data_file, :type => :string, :default => nil
  method_option :max_parallelism, :type => :numeric, :default => nil
  method_option :test_pattern, :type => :string, :default => nil
  method_option :force, :type => :boolean, :default => false
  def spec
    set_shell
    set_default_environment
    git_version_ok
    if git_changes then
      exit_failure(Text::Error::GIT_CHANGES_NOT_COMMITTED) if !options[:force]
      warn(Text::Warning::GIT_CHANGES_NOT_COMMITTED)
    end
    exit_failure unless git_repo? && tddium_settings && suite_for_current_branch?

    test_execution_params = {}

    user_data_file_path = get_remembered_option(options, :user_data_file, nil) do |user_data_file_path|
      if File.exists?(user_data_file_path)
        user_data = File.open(user_data_file_path) { |file| file.read }
        test_execution_params[:user_data_text] = Base64.encode64(user_data)
        test_execution_params[:user_data_filename] = File.basename(user_data_file_path)
      else
        exit_failure Text::Error::NO_USER_DATA_FILE % user_data_file_path
      end
    end

    max_parallelism = get_remembered_option(options, :max_parallelism, nil) do |max_parallelism|
      test_execution_params[:max_parallelism] = max_parallelism
    end
    
    test_pattern = get_remembered_option(options, :test_pattern, nil)

    start_time = Time.now

    # Call the API to get the suite and its tests
    begin
      suite_details = call_api(:get, current_suite_path)

      # Push the latest code to git
      exit_failure unless update_git_remote_and_push(suite_details)

      # Create a session
      new_session = call_api(:post, Api::Path::SESSIONS)
      session_id = new_session["session"]["id"]

      # Register the tests
      call_api(:post, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::REGISTER_TEST_EXECUTIONS}", {:suite_id => current_suite_id, :test_pattern => test_pattern})

      # Start the tests
      start_test_executions = call_api(:post, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::START_TEST_EXECUTIONS}", test_execution_params)
      
      say Text::Process::STARTING_TEST % start_test_executions["started"]

      tests_not_finished_yet = true
      finished_tests = {}
      test_statuses = Hash.new(0)

      say Text::Process::CHECK_TEST_REPORT % start_test_executions["report"]
      say Text::Process::TERMINATE_INSTRUCTION
      while tests_not_finished_yet do
        # Poll the API to check the status
        current_test_executions = call_api(:get, "#{Api::Path::SESSIONS}/#{session_id}/#{Api::Path::TEST_EXECUTIONS}")

        # Catch Ctrl-C to interrupt the test
        Signal.trap(:INT) do
          say Text::Process::INTERRUPT
          say Text::Process::CHECK_TEST_STATUS
          tests_not_finished_yet = false
        end

        # Print out the progress of running tests
        current_test_executions["tests"].each do |test_name, result_params|
          test_status = result_params["status"]
          if result_params["finished"] && !finished_tests[test_name]
            message = case test_status
                        when "passed" then [".", :green, false]
                        when "failed" then ["F", :red, false]
                        when "error" then ["E", nil, false]
                        when "pending" then ["*", :yellow, false]
                        when "skipped" then [".", :yellow, false]
                        else [".", nil, false]
                      end
            finished_tests[test_name] = test_status
            test_statuses[test_status] += 1
            say *message
          end
        end

        # If all tests finished, exit the loop else sleep
        if finished_tests.size == current_test_executions["tests"].size
          tests_not_finished_yet = false
        else
          sleep(Default::SLEEP_TIME_BETWEEN_POLLS)
        end
      end

      # Print out the result
      say ""
      say Text::Process::FINISHED_TEST % (Time.now - start_time)
      say "#{finished_tests.size} tests, #{test_statuses["failed"]} failures, #{test_statuses["error"]} errors, #{test_statuses["pending"]} pending"

      # Save the spec options
      write_suite(suite_details["suite"].merge({"id" => current_suite_id}),
                                    {"user_data_file" => user_data_file_path,
                                     "max_parallelism" => max_parallelism,
                                     "test_pattern" => test_pattern})

      exit_failure if test_statuses["failed"] > 0 || test_statuses["error"] > 0
    rescue TddiumClient::Error::Base
      exit_failure "Failed due to error communicating with Tddium"
    rescue RuntimeError => e
      exit_failure "Failed due to internal error: #{e.inspect} #{e.backtrace}"
    end
  end

  desc "status", "Display information about this suite, and any open dev sessions"
  def status
    set_shell
    set_default_environment
    git_version_ok
    return unless git_repo? && tddium_settings && suite_for_current_branch?

    begin
      current_suites = call_api(:get, Api::Path::SUITES)
      if current_suites["suites"].size == 0
        say Text::Status::NO_SUITE
      else
        if current_suite = current_suites["suites"].detect {|suite| suite["id"] == current_suite_id}
          show_session_details({:active => false, :order => "date", :limit => 10}, Text::Status::NO_INACTIVE_SESSION, Text::Status::INACTIVE_SESSIONS)
          show_session_details({:active => true}, Text::Status::NO_ACTIVE_SESSION, Text::Status::ACTIVE_SESSIONS)
          say Text::Status::SEPARATOR
          say Text::Status::CURRENT_SUITE % current_suite["repo_name"]
          display_attributes(DisplayedAttributes::SUITE, current_suite)
        else
          say Text::Status::CURRENT_SUITE_UNAVAILABLE
        end
      end
    rescue TddiumClient::Error::Base
    end
  end

  desc "suite", "Register the suite for this project, or edit its settings"
  method_option :edit, :type => :boolean, :default => false
  method_option :name, :type => :string, :default => nil
  method_option :pull_url, :type => :string, :default => nil
  method_option :push_url, :type => :string, :default => nil
  method_option :test_pattern, :type => :string, :default => nil
  def suite
    set_default_environment
    git_version_ok
    return unless git_repo? && tddium_settings

    params = {}
    begin
      if current_suite_id
        current_suite = call_api(:get, current_suite_path)["suite"]

        if options[:edit]
          update_suite(current_suite, options)
        else
          say Text::Process::EXISTING_SUITE % format_suite_details(current_suite)
        end
      else
        params[:branch] = current_git_branch
        default_suite_name = File.basename(Dir.pwd)
        params[:repo_name] = options[:name] || default_suite_name

        use_existing_suite, existing_suite = resolve_suite_name(options, params, default_suite_name)

        if use_existing_suite
          # Write to file and exit when using the existing suite
          write_suite(existing_suite)
          say Text::Status::USING_SUITE % format_suite_details(existing_suite)
          return
        end

        prompt_suite_params(options, params)

        params.each do |k,v|
          params.delete(k) if v == 'disable'
        end

        # Create new suite if it does not exist yet
        say Text::Process::CREATING_SUITE % [params[:repo_name], params[:branch]]
        new_suite = call_api(:post, Api::Path::SUITES, {:suite => params})
        # Save the created suite
        write_suite(new_suite["suite"])

        # Manage git
        exit_failure("Failed to push repo to Tddium!") unless update_git_remote_and_push(new_suite)

        say Text::Process::CREATED_SUITE % format_suite_details(new_suite["suite"])
      end
    rescue TddiumClient::Error::Base
      exit_failure
    end
  end

  map "-v" => :version
  desc "version", "Print the tddium gem version"
  def version
    say TddiumVersion::VERSION
  end

  private

  def call_api(method, api_path, params = {}, api_key = nil, show_error = true)
    api_key =  tddium_settings(:fail_with_message => false)["api_key"] if tddium_settings(:fail_with_message => false) && api_key != false
    begin
      result = tddium_client.call_api(method, api_path, params, api_key)
    rescue TddiumClient::Error::Base => e
      say e.message if show_error
      raise e
    end
    result
  end

  def git_changes
    cmd = "(git ls-files --exclude-standard -d -m -t || echo GIT_FAILED) < /dev/null 2>&1"
    p = IO.popen(cmd)
    changes = false
    while line = p.gets do
      if line =~ /GIT_FAILED/
        warn(Text::Warning::GIT_UNABLE_TO_DETECT)
        return false
      end
      line = line.strip
      fields = line.split(/\s+/)
      status = fields[0]
      if status !~ /^\?/ then
        changes = true
        break
      end
    end
    return changes
  end

  def git_version_ok
    version = nil
    begin
      version_string = `git --version`
      m =  version_string.match(Dependency::VERSION_REGEXP)
      version = m[0] unless m.nil?
    rescue Errno
    rescue Exception
    end
    if version.nil? || version.empty? then
      exit_failure(Text::Error::GIT_NOT_FOUND)
    end
    version_parts = version.split(".")
    if version_parts[0].to_i < 1 ||
       version_parts[1].to_i < 7 then
      warn(Text::Warning::GIT_VERSION % version)
    end
  end

  def current_git_branch
    @current_git_branch ||= `git symbolic-ref HEAD`.gsub("\n", "").split("/")[2..-1].join("/")
  end

  def current_suite_id
    tddium_settings["branches"][current_git_branch]["id"] if tddium_settings["branches"] && tddium_settings["branches"][current_git_branch]
  end

  def current_suite_options
    if tddium_settings["branches"] && tddium_settings["branches"][current_git_branch]
      tddium_settings["branches"][current_git_branch]["options"]
    end || {}
  end

  def current_suite_path
    "#{Api::Path::SUITES}/#{current_suite_id}"
  end

  def dependency_version(command)
    result = `#{command} -v`.strip
    say Text::Process::DEPENDENCY_VERSION % [command, result]
    result
  end

  def display_attributes(names_to_display, attributes)
    names_to_display.each do |attr|
      say Text::Status::ATTRIBUTE_DETAIL % [attr.gsub("_", " ").capitalize, attributes[attr]] if attributes[attr]
    end
  end

  def environment
    tddium_client.environment.to_sym
  end

  def warn(msg='')
    STDERR.puts("WARNING: #{msg}")
  end

  def exit_failure(msg='')
    abort msg
  end

  def get_remembered_option(options, key, default, &block)
    remembered = false
    if options[key] != default
      result = options[key]
    elsif remembered = current_suite_options[key.to_s]
      result = remembered
      remembered = true
    else
      result = default
    end
    
    if result
      msg = Text::Process::USING_SPEC_OPTION[key] % result
      msg +=  Text::Process::REMEMBERED if remembered
      msg += "\n"
      say msg
      yield result if block_given?
    end
    result
  end

  def get_user
    call_api(:get, Api::Path::USERS, {}, nil, false) rescue nil
  end

  def get_user_credentials(options = {})
    params = {}
    # prompt for email/invitation and password
    if options[:invited]
      token = options[:invitation_token] || ask(Text::Prompt::INVITATION_TOKEN)
      params[:invitation_token] = token.strip
    else
      params[:email] = options[:email] || ask(Text::Prompt::EMAIL)
    end
    params[:password] = options[:password] || HighLine.ask(Text::Prompt::PASSWORD) { |q| q.echo = "*" }
    params
  end

  def git_push
    say Text::Process::GIT_PUSH
    system("git push -f #{Git::REMOTE_NAME} #{current_git_branch}")
  end

  def git_repo?
    unless system("test -d .git || git status > /dev/null 2>&1")
      message = Text::Error::GIT_NOT_INITIALIZED
      say message
    end
    message.nil?
  end

  def git_origin_url
    result = `(git config --get remote.origin.url || echo GIT_FAILED) 2>/dev/null`
    return nil if result =~ /GIT_FAILED/
    if result =~ /@/
      result.strip
    else
      nil
    end
  end

  def handle_heroku_user(options, heroku_config)
    api_key = heroku_config['TDDIUM_API_KEY']
    user = tddium_client.call_api(:get, Api::Path::USERS, {}, api_key) rescue nil
    exit_failure Text::Error::HEROKU_MISCONFIGURED % "Unrecognized user" unless user
    say Text::Process::HEROKU_WELCOME % user["user"]["email"]

    if user["user"]["heroku_needs_activation"] == true
      say Text::Process::HEROKU_ACTIVATE
      params = get_user_credentials(:email => heroku_config['TDDIUM_USER_NAME'])
      params.delete(:email)
      params[:password_confirmation] = HighLine.ask(Text::Prompt::PASSWORD_CONFIRMATION) { |q| q.echo = "*" }
      begin
        params[:user_git_pubkey] = prompt_ssh_key(options[:ssh_key])
      rescue TddiumError => e
        exit_failure e.message
      end

      begin
        user_id = user["user"]["id"]
        result = tddium_client.call_api(:put, "#{Api::Path::USERS}/#{user_id}/", {:user=>params, :heroku_activation=>true}, api_key)
      rescue TddiumClient::Error::API => e
        exit_failure Text::Error::HEROKU_MISCONFIGURED % e
      rescue TddiumClient::Error::Base => e
        exit_failure Text::Error::HEROKU_MISCONFIGURED % e
      end
    end
    
    write_api_key(user["user"]["api_key"])
    say Text::Status::HEROKU_CONFIG 
  end

  def login_user(options = {})
    # POST (email, password) to /users/sign_in to retrieve an API key
    begin
      login_result = call_api(:post, Api::Path::SIGN_IN, {:user => options[:params]}, false, options[:show_error])
      # On success, write the API key to "~/.tddium.<environment>"
      write_api_key(login_result["api_key"])
    rescue TddiumClient::Error::Base
    end
    login_result
  end

  def prompt(text, current_value, default_value)
    value = current_value || ask(text % default_value, :bold)
    value.empty? ? default_value : value
  end

  def prompt_ssh_key(current)
    # Prompt for ssh-key file
    ssh_file = prompt(Text::Prompt::SSH_KEY, options[:ssh_key_file], Default::SSH_FILE)
    data = File.open(File.expand_path(ssh_file)) {|file| file.read}
    if data =~ /^-+BEGIN [DR]SA PRIVATE KEY-+/ then
      raise TddiumError.new(Text::Error::INVALID_SSH_PUBLIC_KEY % ssh_file)
    end
    if data !~ /^\s*ssh-(dss|rsa)/ then
      raise TddiumError.new(Text::Error::INVALID_SSH_PUBLIC_KEY % ssh_file)
    end
    data
  end

  def prompt_suite_params(options, params, current={})
    say Text::Process::DETECTED_BRANCH % params[:branch] if params[:branch]
    params[:ruby_version] = dependency_version(:ruby)
    params[:bundler_version] = dependency_version(:bundle)
    params[:rubygems_version] = dependency_version(:gem)

    ask_or_update = lambda do |key, text, default|
      params[key] = prompt(text, options[key], current.fetch(key.to_s, default))
    end

    ask_or_update.call(:test_pattern, Text::Prompt::TEST_PATTERN, Default::SUITE_TEST_PATTERN)

    if current.size > 0 && current['ci_pull_url']
      say(Text::Process::SETUP_CI_EDIT)
    else
      say(Text::Process::SETUP_CI_FIRST_TIME % params[:test_pattern])
    end

    ask_or_update.call(:ci_pull_url, Text::Prompt::CI_PULL_URL, git_origin_url) 
    ask_or_update.call(:ci_push_url, Text::Prompt::CI_PUSH_URL, nil)

    if current.size > 0 && current['campfire_room']
      say(Text::Process::SETUP_CAMPFIRE_EDIT)
    else
      say(Text::Process::SETUP_CAMPFIRE_FIRST_TIME)
    end

    subdomain = ask_or_update.call(:campfire_subdomain, Text::Prompt::CAMPFIRE_SUBDOMAIN, nil)
    if !subdomain.nil? && subdomain != 'disable' then
      ask_or_update.call(:campfire_token, Text::Prompt::CAMPFIRE_TOKEN, nil)
      ask_or_update.call(:campfire_room, Text::Prompt::CAMPFIRE_ROOM, nil)
    end
  end

  def update_suite(suite, options)
    params = {}
    prompt_suite_params(options, params, suite)
    call_api(:put, "#{Api::Path::SUITES}/#{suite['id']}", params)
    say Text::Process::UPDATED_SUITE
  end

  def resolve_suite_name(options, params, default_suite_name)
    # XXX updates params
    existing_suite = nil
    use_existing_suite = false
    suite_name_resolved = false
    while !suite_name_resolved
      # Check to see if there is an existing suite
      current_suites = call_api(:get, Api::Path::SUITES, params)
      existing_suite = current_suites["suites"].first

      # Get the suite name
      current_suite_name = params[:repo_name]
      if existing_suite
        # Prompt for using existing suite (unless suite name is passed from command line) or entering new one
        params[:repo_name] = prompt(Text::Prompt::USE_EXISTING_SUITE % params[:branch], options[:name], current_suite_name)
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
    end
    [use_existing_suite, existing_suite]
  end

  def set_shell
    if !$stdout.tty? || !$stderr.tty? then
      @shell = Thor::Shell::Basic.new
    end
  end

  def set_default_environment
    env = options[:environment] || ENV['TDDIUM_CLIENT_ENVIRONMENT']
    if env.nil?
      tddium_client.environment = :development
      tddium_client.environment = :production unless File.exists?(tddium_file_name)
    else
      tddium_client.environment = env.to_sym
    end

    port = options[:port] || ENV['TDDIUM_CLIENT_PORT']
    if port
      tddium_client.port = port.to_i
    end
  end

  def show_session_details(params, no_session_prompt, all_session_prompt)
    begin
      current_sessions = call_api(:get, Api::Path::SESSIONS, params)
      say Text::Status::SEPARATOR
      if current_sessions["sessions"].size == 0
        say no_session_prompt
      else
        say all_session_prompt
        current_sessions["sessions"].reverse_each do |session|
          session_id = session.delete("id")
          say Text::Status::SESSION_TITLE % session_id
          display_attributes(DisplayedAttributes::TEST_EXECUTION, session)
        end
      end
    rescue TddiumClient::Error::Base
    end
  end

  def show_user_details(api_response)
    # Given the user is logged in, she should be able to use "tddium account" to display information about her account:
    # Email address
    # Account creation date
    user = api_response["user"]
    say ERB.new(Text::Status::USER_DETAILS).result(binding)

    begin
      current_suites = call_api(:get, Api::Path::SUITES)
      if current_suites["suites"].size == 0 then
        say Text::Status::NO_SUITE
      else
        say Text::Status::ALL_SUITES % current_suites["suites"].collect {|suite| suite["repo_name"]}.join(", ")
      end

      memberships = call_api(:get, Api::Path::MEMBERSHIPS)
      if memberships["memberships"].length > 1
        say Text::Status::ACCOUNT_MEMBERS
        say memberships["memberships"].collect{|x|x['display']}.join("\n")
        say "\n"
      end

      account_usage = call_api(:get, Api::Path::ACCOUNT_USAGE)
      say account_usage["usage"]
    rescue TddiumClient::Error::Base => e
puts "EXN: #{e.inspect}"
    end
  end

  def format_suite_details(suite)
    # Given an API response containing a "suite" key, compose a string with
    # important information about the suite
    details = ERB.new(Text::Status::SUITE_DETAILS).result(binding)
    details
  end

  def tddium_deploy_key_file_name
    extension = ".#{environment}" unless environment == :production
    ".tddium-deploy-key#{extension}"
  end

  def suite_for_current_branch?
    unless current_suite_id
      message = Text::Error::NO_SUITE_EXISTS % current_git_branch
      say message
    end
    message.nil?
  end

  def tddium_client
    @tddium_client ||= TddiumClient::Client.new
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

  def update_git_remote_and_push(suite_details)
    git_repo_uri = suite_details["suite"]["git_repo_uri"]
    unless `git remote show -n #{Git::REMOTE_NAME}` =~ /#{git_repo_uri}/
      `git remote rm #{Git::REMOTE_NAME} > /dev/null 2>&1`
      `git remote add #{Git::REMOTE_NAME} #{git_repo_uri}`
    end
    git_push
  end

  def user_logged_in?(active = true, message = false)
    result = tddium_settings(:fail_with_message => message) && tddium_settings["api_key"]
    (result && active) ? get_user : result
  end

  def write_api_key(api_key)
    settings = tddium_settings(:fail_with_message => false) || {}
    File.open(tddium_file_name, "w") do |file|
      file.write(settings.merge({"api_key" => api_key}).to_json)
    end
    write_tddium_to_gitignore
  end

  def write_suite(suite, options = {})
    suite_id = suite["id"]
    branches = tddium_settings["branches"] || {}
    branches.merge!({current_git_branch => {"id" => suite_id, "options" => options}})
    File.open(tddium_file_name, "w") do |file|
      file.write(tddium_settings.merge({"branches" => branches}).to_json)
    end
    File.open(tddium_deploy_key_file_name, "w") do |file|
      file.write(suite["ci_ssh_pubkey"])
    end
    write_tddium_to_gitignore
  end

  def write_tddium_to_gitignore
    content = File.exists?(Git::GITIGNORE) ? File.read(Git::GITIGNORE) : ''
    [tddium_file_name, tddium_deploy_key_file_name].each do |fn|
      unless content.include?("#{fn}\n")
        File.open(Git::GITIGNORE, "a") do |file|
          file.write("#{fn}\n")
        end
      end
    end
  end
end
