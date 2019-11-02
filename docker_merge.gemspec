# frozen_string_literal: true

Gem::Specification.new do |s|
  s.name        = 'docker_merge'
  s.version     = '1.0.0'
  s.date        = '2019-11-02'
  s.summary     = 'Merge Docker images'
  s.description = 'Merge layers from multiple Docker images'
  s.authors     = ['Nathan Broadbent']
  s.email       = 'nathan@formapi.io'
  s.files       = ['lib/docker_merge.rb']
  s.executables = ['docker_merge']
  s.homepage    = 'https://rubygems.org/gems/docker_merge'
  s.license = 'MIT'

  s.add_development_dependency 'minitest', '~> 5.13', '>= 5.13.0'
  s.add_development_dependency 'pry-byebug', '~> 3.7', '>= 3.7.0'
  s.add_development_dependency 'rake', '~> 12.3', '>= 12.3.1'
  s.add_development_dependency 'rubocop', '~> 0.76', '>= 0.76.0'
end
