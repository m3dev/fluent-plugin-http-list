# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.name          = "fluent-plugin-http-list"
  gem.version       = "0.0.1"
  gem.authors       = ["Paul McCann"]
  gem.email         = ["p-mccann@m3.com"]
  gem.description   = %q{fluent plugin to accept multiple events in one HTTP request}
  gem.summary       = %q{fluent plugin to accept multiple events in one HTTP request}
  gem.homepage      = "https://github.com/m3dev/fluent-plugin-http-list"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "fluentd"
  gem.add_runtime_dependency "fluentd"
end
