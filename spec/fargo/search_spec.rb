require 'spec_helper'

RSpec::Matchers.define :match_hash do |hash|
  match do |search|
    search.matches? hash
  end

  failure_message_for_should do |search|
    "#{search.to_s} should have matched the hash: #{hash.inspect}"
  end
end

RSpec::Matchers.define :match_file do |file|
  match do |search|
    search.matches? :file => file
  end

  failure_message_for_should do |search|
    "#{search.to_s} should have matched the file: #{file}"
  end
end

describe Fargo::Search do
  it "matches based on file names" do
    subject.query = 'foo bar'

    subject.should match_file('foobar.mkv')
    subject.should match_file('foo/bar.avi')
    subject.should_not match_file('foo.avi')
    subject.should_not match_file('bar.jpg')
  end

  it "filters based off of the maximum size of the file" do
    subject.query           = 'foo'
    subject.size            = 100
    subject.size_restricted = true

    subject.should match_hash(:file => 'foo', :size => 50)
    subject.should_not match_hash(:file => 'foo', :size => 101)
  end

  it "filters based off of the minimum size of the file" do
    subject.query           = 'foo'
    subject.size            = 100
    subject.size_restricted = true
    subject.is_minimum_size = true

    subject.should_not match_hash(:file => 'foo', :size => 50)
    subject.should match_hash(:file => 'foo', :size => 101)
  end

  it "matches based on TTH values" do
    subject.query = 'TTH:foobar'
    subject.filetype = Fargo::Search::TTH

    subject.should match_hash(:tth => 'foobar')
  end

  it "doesn't match on tth if not specified" do
    subject.query = 'TTH:foobar'

    subject.should_not match_hash(:tth => 'foobar')
  end

  it "extracts the query from the pattern specified" do
    subject.pattern = 'a$b$c'
    subject.query.should == 'a b c'
  end

  it "matches valid file names with a filetype of ANY" do
    subject.query = 'foo bar baz'
    subject.filetype = Fargo::Search::ANY

    subject.should match_file('foo/bar.baz')
    subject.should match_file('foo/bar/baz')
    subject.should match_file('foo/a/barb/bazc')
    subject.should match_file('foo.bar.baz')

    subject.should_not match_file('foo.bar')
    subject.should_not match_file('foo.babaz')
    subject.should_not match_file('bar/baz')
  end

  it "only matches audio with a filetype of AUDIO" do
    subject.query = 'foo'
    subject.filetype = Fargo::Search::AUDIO

    subject.should match_file('foo.mp3')
    subject.should match_file('foo.wav')
    subject.should match_file('foo.flac')
    subject.should match_file('foo.m4a')

    subject.should_not match_file('foo.avi')
    subject.should_not match_file('foo.jpg')
    subject.should_not match_file('foo.mov')
  end

  it "only matches videos with a filetype of VIDEOS" do
    subject.query = 'foo'
    subject.filetype = Fargo::Search::VIDEO

    subject.should match_file('foobar.mkv')
    subject.should match_file('foo/bar.avi')
    subject.should match_file('foobar.mov')
    subject.should match_file('foobar.mpeg')
    subject.should match_file('foobar.mpg')

    subject.should_not match_file('foobar')
    subject.should_not match_file('foobar.jpg')
    subject.should_not match_file('foo.bar')
  end
end
