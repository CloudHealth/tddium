# Copyright (c) 2011, 2012, 2013, 2014 Solano Labs All Rights Reserved

require 'rubygems'
require 'aruba/cucumber'
require 'aruba/in_process'
require 'pickle/parser'
require 'tddium/runner'

def prepend_path(path)
  path = File.expand_path(File.dirname(__FILE__) + "/../../#{path}")
  ENV['PATH'] = "#{path}#{File::PATH_SEPARATOR}#{ENV['PATH']}"
end

prepend_path('bin')
#ENV['COVERAGE'] = "true"
ENV['COVERAGE_ROOT'] = "#{File.expand_path(File.dirname(__FILE__) + '/../../')}"

Aruba::InProcess.main_class = Tddium::Runner
Aruba.process = Aruba::InProcess
