require "codeclimate-test-reporter"
CodeClimate::TestReporter.start

$LOAD_PATH.unshift File.expand_path('../../lib', __FILE__)
require 'mutagen'

require "minitest/reporters"
Minitest::Reporters.use! [MiniTest::Reporters::DefaultReporter.new(color: true)]
#Minitest::Reporters.use! Minitest::Reporters::SpecReporter.new

require 'minitest/autorun'