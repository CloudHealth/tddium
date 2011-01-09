=begin
Copyright (c) 2010 tddium.com All Rights Reserved
=end

#
# tddium support methods
#
#

require 'rubygems'
require 'highline/import'
require 'fog'
require 'net/http'
require 'uri'
require 'yaml'

ALREADY_CONFIGURED =<<'EOF'

tddium has already been initialized.

(settings are in %s)

Use 'tddium config:reset' to clear configuration, and then run 'tddium config:init' again.
EOF


CONFIG_FILE_PATH = File.expand_path('~/.tddium')

def write_config(config)
  File.open(CONFIG_FILE_PATH, 'w', 0600) do |f|
    YAML.dump(config, f)
  end
end

def init_task
  if File.exists?(CONFIG_FILE_PATH) then
    puts ALREADY_CONFIGURED % CONFIG_FILE_PATH
  else
    conf = {}
    conf[:aws_key] = ask('Enter AWS Access Key: ')
    conf[:aws_secret] = ask('Enter AWS Secret: ')
    conf[:test_pattern] = ask('Enter filepattern for tests: ') { |q|
      q.default='**/*_spec.rb'
    }
    conf[:key_directory] = ask('Enter directory for secret key(s): ') { |q|
      q.default='spec/secret'
    }
    conf[:key_name] = ask('Enter secret key name (excluding .pem suffix): ') { |q|
      q.default='sg-keypair'
    }
    conf[:result_directory] = ask('Enter directory for result reports: ') { |q|
      q.default='results'
    }
    conf[:server_tag] = ask("(optional) Enter tag=value to give instances: ") 

    write_config conf
  end
end

def read_config
  defaults = {
    :aws_key => nil,
    :aws_secret => nil,
    :test_pattern => '**/*_test.rb',
    :key_name => nil,
    :key_directory => nil,
    :result_directory => 'results',
  }

  if File.exists?(CONFIG_FILE_PATH) then
    file_conf = YAML.load(File.read(CONFIG_FILE_PATH))
  else
    file_conf = {}
  end
  defaults.merge(file_conf)
end

# If the config file isn't YAML -- doesn't start with '---', convert it into
# YAML.
def convert_old_config
  oldpath = CONFIG_FILE_PATH + '.old'
  FileUtils.rm_f oldpath

  old_data = File.readlines(CONFIG_FILE_PATH)[0]
  unless old_data.match /^---/ then
    oldconf = read_old_config

    FileUtils.mv CONFIG_FILE_PATH, oldpath

    write_config oldconf
  end
end

#
def read_old_config(filename=CONFIG_FILE_PATH)
  conf = {
    :aws_key => nil,
    :aws_secret => nil,
    :test_pattern => '**/*_test.rb',
    :key_name => nil,
    :key_directory => nil,
    :result_directory => 'results',
  }
  if File.exists?(filename) then
    File.open(filename) do |f|
      f.each do |line|
        key, val = line.split(': ')
        conf[key.to_sym] = val.chomp
      end
    end
  end
  conf
end
  

AMI_NAME = 'ami-b0a253d9'

def start_instance
  conf = read_config
  @tddium_session = rand(2**64-1).to_s(36)

  key_file = nil
  if !conf[:key_name].nil? && !conf[:key_directory].nil?
    key_file = File.join(conf[:key_directory], "#{conf[:key_name]}.pem")
    STDERR.puts "No key file #{key_file} with x00 permissions present" unless File.exists?(key_file) && (File.stat(key_file).mode & "77".to_i(8) == 0)
  end

  @ec2pool = Fog::AWS::Compute.new(:aws_access_key_id => conf[:aws_key],
                                   :aws_secret_access_key => conf[:aws_secret])

  server = @ec2pool.servers.create(:flavor_id => 'm1.large',
                                   :groups => ['selenium-grid'],
                                   :image_id => AMI_NAME,
                                   :name => 'sg-server',
                                   :key_name => conf[:key_name])

  @ec2pool.tags.create(:key => 'tddium_session', 
                       :value => @tddium_session,
                       :resource_id => server.id)

  server_tag = conf[:server_tag].split('=')

  @ec2pool.tags.create(:key => server_tag[0],
                       :value => server_tag[1],
                       :resource_id => server.id)

  server.wait_for { ready? }
  server.reload

  puts "started instance #{server.id} #{server.dns_name} in group #{server.groups} with tags #{server.tags.inspect}"

  uri = URI.parse("http://#{server.dns_name}:4445/console")
  http = Net::HTTP.new(uri.host, uri.port)
  http.open_timeout = 60
  http.read_timeout = 60

  rc_up = false
  tries = 0
  while !rc_up && tries < 5
    begin
      http.request(Net::HTTP::Get.new(uri.request_uri))
      rc_up = true
    rescue Errno::ECONNREFUSED
      sleep 5
    rescue Timeout::Error
    ensure
      tries += 1
    end
  end
  raise "Couldn't connect to #{uri.request_uri}" unless rc_up

  puts "Selenium Console:"
  puts "#{uri}"

  if !key_file.nil?
    STDERR.puts "You can login via \"ssh -i #{key_file} ec2-user@#{server.dns_name}\""
    STDERR.puts "Making /var/log/messages world readable"
    system "ssh -i #{key_file} ec2-user@#{server.dns_name} 'sudo chmod 644 /var/log/messages'"
  else
    # TODO: Remove when /var/log/messages bug is fixed
    STDERR.puts "No key_file provided.  /var/log/messages may not be readable by ec2-user."
  end
  server
end

#
# Prepare the result directory, as specified by config[:result_directory].
#
# If the directory doesn't exist create it, and a latest subdirectory.
#
# If the latest subdirectory exists, rotate it and create a new empty latest.
#
def result_directory
  conf = read_config
  latest = File.join(conf[:result_directory], 'latest')

  if File.directory?(latest) then
    mtime = File.stat(latest).mtime.strftime("%Y%m%d-%H%M%S")
    archive = File.join(conf[:result_directory], mtime)
    FileUtils.mv(latest, archive)
  end
  FileUtils.mkdir_p latest
  latest
end

REPORT_FILENAME = "selenium_report.html"

def default_report_path
  File.join(read_config[:result_directory], 'latest', REPORT_FILENAME)
end

def stop_instance
  conf = read_config
  @ec2pool = Fog::AWS::Compute.new(:aws_access_key_id => conf[:aws_key],
                              :aws_secret_access_key => conf[:aws_secret])

  # TODO: The logic here is a bit convoluted now
  @ec2pool.servers.select{|s| s.image_id == AMI_NAME}.each do |s|
    # in Fog 0.3.33, :filters is buggy and won't accept resourceId or resource_id
    tags = @ec2pool.tags(:filters => {:key => 'tddium_session'}).select{|t| t.resource_id == s.id}
    if tags.first.value == @tddium_session then
      STDERR.puts "stopping instance #{s.id} #{s.dns_name} from our session"
      s.destroy
    else
      STDERR.puts "skipping instance #{s.id} #{s.dns_name} created in another session"
    end
  end
  nil
end
