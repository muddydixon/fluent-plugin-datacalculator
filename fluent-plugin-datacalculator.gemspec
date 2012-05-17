# -*- encoding: utf-8 -*-
$:.push File.expand_path("../lib", __FILE__)

Gem::Specification.new do |s|
  s.name        = "fluent-plugin-datacalculator"
  s.version     = "0.0.0"
  s.authors     = ["Muddy Dixon"]
  s.email       = ["muddydixon@gmail.com"]
  s.homepage    = "https://github.com/muddydixon/fluent-plugin-datacalculator"
  s.summary     = %q{Output filter plugin to calculate messages that matches specified conditions}
  s.description = %q{Output filter plugin to calculate messages that matches specified conditions}

  s.rubyforge_project = "fluent-plugin-datacalculator"

  s.files         = `git ls-files`.split("\n")
  s.test_files    = `git ls-files -- {test,spec,features}/*`.split("\n")
  s.executables   = `git ls-files -- bin/*`.split("\n").map{ |f| File.basename(f) }
  s.require_paths = ["lib"]

  # specify any dependencies here; for example:
  # s.add_development_dependency "rspec"
  # s.add_runtime_dependency "rest-client"
  s.add_development_dependency "fluentd"
  s.add_runtime_dependency "fluentd"
end
