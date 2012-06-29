require "bundler/gem_tasks"

require 'rake/testtask'
Rake::TestTask.new(:test) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_*.rb'
  test.verbose = true
end

desc "fomulas test"
Rake::TestTask.new(:fomulas) do |test|
  test.libs << 'lib' << 'test'
  test.pattern = 'test/**/test_out_datacalculator_fomulas.rb'
  test.verbose = true
end

task :default => :test

