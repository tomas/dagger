# -*- encoding: utf-8 -*-
require File.expand_path("../lib/dagger/version", __FILE__)

Gem::Specification.new do |s|
  s.name        = "dagger"
  s.version     = Dagger::VERSION
  s.platform    = Gem::Platform::RUBY
  s.authors     = ['Tomás Pollak']
  s.email       = ['tomas@forkhq.com']
  s.homepage    = "https://github.com/tomas/dagger"
  s.summary     = "Simplified Net::HTTP wrapper."
  s.description = "Dagger.post(url, params).body"

  s.required_rubygems_version = ">= 1.3.6"
  s.rubyforge_project         = "dagger"

  s.add_development_dependency "bundler", ">= 1.0.0"

  s.files        = `git ls-files`.split("\n")
  s.executables  = `git ls-files`.split("\n").map{|f| f =~ /^bin\/(.*)/ ? $1 : nil}.compact
  s.require_path = 'lib'
  # s.bindir       = 'bin'
end
