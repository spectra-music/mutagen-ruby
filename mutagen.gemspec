# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'mutagen/version'

Gem::Specification.new do |spec|
  spec.name          = 'mutagen'
  spec.version       = Mutagen::VERSION
  spec.authors       = ['Katherine Whitlock']
  spec.email         = ['toroidalcode@gmail.com']
  spec.summary       = %q{A Ruby version of the fantastic Mutagen tag editing library.}
  spec.description   = ''
  spec.homepage      = ''
  spec.license       = 'MIT'

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ['lib']

  spec.add_development_dependency 'bundler', '~> 1.6'
  spec.add_development_dependency 'rake', '~> 10'
  spec.add_development_dependency 'rspec', '~> 3'
  spec.add_development_dependency 'minitest', '>= 0'
  spec.add_development_dependency 'minitest-reporters', '~> 1.0.4'
  spec.add_development_dependency 'yard', '~> 0.8'
end
