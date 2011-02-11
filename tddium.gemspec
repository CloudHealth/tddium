# Generated by jeweler
# DO NOT EDIT THIS FILE DIRECTLY
# Instead, edit Jeweler::Tasks in Rakefile, and run 'rake gemspec'
# -*- encoding: utf-8 -*-

Gem::Specification.new do |s|
  s.name = %q{tddium}
  s.version = "0.4.2"

  s.required_rubygems_version = Gem::Requirement.new(">= 0") if s.respond_to? :required_rubygems_version=
  s.authors = ["Jay Moorthi"]
  s.date = %q{2011-02-11}
  s.default_executable = %q{tddium}
  s.description = %q{tddium gets your rspec+selenium tests into the cloud by running them on your VMs}
  s.email = %q{info@tddium.com}
  s.executables = ["tddium"]
  s.extra_rdoc_files = [
    "LICENSE.txt",
    "README.rdoc"
  ]
  s.files = [
    ".document",
    "CHANGELOG",
    "Gemfile",
    "Gemfile.lock",
    "LICENSE.txt",
    "README.rdoc",
    "Rakefile",
    "VERSION",
    "bin/tddium",
    "doc/aws-keypair-example.tiff",
    "doc/aws-secgroup-example.tiff",
    "lib/spec_storm/action_controller_ext.rb",
    "lib/spec_storm/action_view_ext.rb",
    "lib/spec_storm/active_record_ext.rb",
    "lib/tddium.rb",
    "lib/tddium/config.rb",
    "lib/tddium/instance.rb",
    "lib/tddium/parallel.rb",
    "lib/tddium/rails.rb",
    "lib/tddium/reporting.rb",
    "lib/tddium/ssh.rb",
    "lib/tddium/taskalias.rb",
    "lib/tddium/tasks.rb",
    "lib/tddium_helper.rb",
    "lib/tddium_loader.rb",
    "parallelrun",
    "rails/init.rb",
    "tddium.gemspec",
    "test/helper.rb",
    "test/test_config.rb",
    "test/test_parallel.rb",
    "test/test_tddium.rb"
  ]
  s.homepage = %q{http://www.tddium.com/}
  s.require_paths = ["lib"]
  s.rubygems_version = %q{1.3.7}
  s.summary = %q{tddium Cloud Test Runner}
  s.test_files = [
    "test/helper.rb",
    "test/test_config.rb",
    "test/test_parallel.rb",
    "test/test_tddium.rb"
  ]

  if s.respond_to? :specification_version then
    current_version = Gem::Specification::CURRENT_SPECIFICATION_VERSION
    s.specification_version = 3

    if Gem::Version.new(Gem::VERSION) >= Gem::Version.new('1.2.0') then
      s.add_runtime_dependency(%q<highline>, [">= 0"])
      s.add_runtime_dependency(%q<rspec>, ["> 1.2.6", "< 2.0.0"])
      s.add_runtime_dependency(%q<parallel>, [">= 0"])
      s.add_runtime_dependency(%q<selenium-client>, [">= 1.2.18"])
      s.add_runtime_dependency(%q<fog>, ["= 0.4.0"])
      s.add_development_dependency(%q<shoulda>, [">= 0"])
      s.add_development_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_development_dependency(%q<jeweler>, ["~> 1.5.1"])
      s.add_development_dependency(%q<rcov>, [">= 0"])
      s.add_development_dependency(%q<mocha>, [">= 0"])
      s.add_development_dependency(%q<fakefs>, [">= 0.3.1"])
      s.add_development_dependency(%q<rails>, ["= 2.3.8"])
    else
      s.add_dependency(%q<highline>, [">= 0"])
      s.add_dependency(%q<rspec>, ["> 1.2.6", "< 2.0.0"])
      s.add_dependency(%q<parallel>, [">= 0"])
      s.add_dependency(%q<selenium-client>, [">= 1.2.18"])
      s.add_dependency(%q<fog>, ["= 0.4.0"])
      s.add_dependency(%q<shoulda>, [">= 0"])
      s.add_dependency(%q<bundler>, ["~> 1.0.0"])
      s.add_dependency(%q<jeweler>, ["~> 1.5.1"])
      s.add_dependency(%q<rcov>, [">= 0"])
      s.add_dependency(%q<mocha>, [">= 0"])
      s.add_dependency(%q<fakefs>, [">= 0.3.1"])
      s.add_dependency(%q<rails>, ["= 2.3.8"])
    end
  else
    s.add_dependency(%q<highline>, [">= 0"])
    s.add_dependency(%q<rspec>, ["> 1.2.6", "< 2.0.0"])
    s.add_dependency(%q<parallel>, [">= 0"])
    s.add_dependency(%q<selenium-client>, [">= 1.2.18"])
    s.add_dependency(%q<fog>, ["= 0.4.0"])
    s.add_dependency(%q<shoulda>, [">= 0"])
    s.add_dependency(%q<bundler>, ["~> 1.0.0"])
    s.add_dependency(%q<jeweler>, ["~> 1.5.1"])
    s.add_dependency(%q<rcov>, [">= 0"])
    s.add_dependency(%q<mocha>, [">= 0"])
    s.add_dependency(%q<fakefs>, [">= 0.3.1"])
    s.add_dependency(%q<rails>, ["= 2.3.8"])
  end
end

