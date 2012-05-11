# Copyright (c) 2011, 2012 Solano Labs All Rights Reserved

module Tddium
  class TddiumCli < Thor
    desc "keys", "List SSH keys authorized for Tddium"
    def keys
      tddium_setup({:git => false})

      begin
        keys_details = @tddium_api.get_keys
        show_keys_details(keys_details)
      rescue TddiumClient::Error::API => e
        exit_failure Text::Error::LIST_KEYS_ERROR
      end
    end

    desc "keys:add [NAME] [PATH]", "Authorize an existing keypair for Tddium"
    method_option :dir, :type=>:string, :default=>nil
    define_method "keys:add" do |name, path|
      tddium_setup({:git => false})

      output_dir = options[:dir] || ENV['TDDIUM_GEM_KEY_DIR']
      output_dir ||= Default::SSH_OUTPUT_DIR

      begin
        keys_details = @tddium_api.get_keys
        if keys_details.count{|x|x['name'] == name} > 0
          exit_failure Text::Error::ADD_KEYS_DUPLICATE % name
        end

        say Text::Process::ADD_KEYS_ADD % name
        keydata = Tddium::Ssh.load_ssh_key(path, name)
        result = @tddium_api.set_keys({:keys => [keydata]})

        say Text::Process::ADD_KEYS_ADD_DONE % [name, result["git_server"] || Default::GIT_SERVER, path]

      rescue TddiumClient::Error::API => e
        exit_failure Text::Error::ADD_KEYS_ERROR % name
      rescue TddiumError => e
        exit_failure e.message
      end
    end

    map "generate" => :gen
    desc "keys:gen [NAME]", "Generate and authorize a keypair for Tddium"
    method_option :dir, :type=>:string, :default=>nil
    define_method "keys:gen" do |name|
      tddium_setup({:git => false})

      output_dir = options[:dir] || ENV['TDDIUM_GEM_KEY_DIR']
      output_dir ||= Default::SSH_OUTPUT_DIR

      begin
        keys_details = @tddium_api.get_keys
        if keys_details.count{|x|x['name'] == name} > 0
          exit_failure Text::Error::ADD_KEYS_DUPLICATE % name
        end

        say Text::Process::ADD_KEYS_GENERATE % name
        keydata = Tddium::Ssh.generate_keypair(name, output_dir)
        
        result = @tddium_api.set_keys({:keys => [keydata]})
        outfile = File.expand_path(File.join(output_dir, "identity.tddium.#{name}"))
        say Text::Process::ADD_KEYS_GENERATE_DONE % [name, result["git_server"] || Default::GIT_SERVER, outfile]

      rescue TddiumClient::Error::API => e
        exit_failure Text::Error::ADD_KEYS_ERROR % name
      rescue TddiumError => e
        exit_failure e.message
      end
    end

    desc "keys:remove [NAME]", "Remove a key that was authorized for Tddium"
    define_method "keys:remove" do |name|
      tddium_setup({:git => false})

      begin
        say Text::Process::REMOVE_KEYS % name
        result = @tddium_api.delete_keys(name)
        say Text::Process::REMOVE_KEYS_DONE % name
      rescue TddiumClient::Error::API => e
        exit_failure Text::Error::REMOVE_KEYS_ERROR % name
      end
    end
  end
end  
