require 'spec_helper'
require 'active_support/core_ext/string/strip'

describe Fargo::CLI::NickBrowser, :type => :emsync do

  subject { Fargo::CLI::Console.new }

  before :each do
    subject.client = Fargo::Client.new
    subject.log_published_messages
    subject.setup_console
  end

  def capture(*streams)
    streams.map! { |stream| stream.to_s }
    begin
      result = StringIO.new
      streams.each { |stream| eval "$#{stream} = result" }
      yield
    ensure
      streams.each { |stream| eval("$#{stream} = #{stream.upcase}") }
    end
    result.string
  end

  it "asks the client to browse the specified nick" do
    subject.client.should_receive(:file_list).with('foobar')
    subject.browse 'foobar'
  end

  it "doesn't like listing directories when no one is being browsed" do
    capture(:stdout) { subject.ls }.should =~ /not browsing/i
  end

  it "prints out nothing when not browsing any one" do
    capture(:stdout) { subject.pwd }.should_not =~ /\//
  end

  it "asks for the parsed file list" do
    subject.client.should_receive(:parsed_file_list).with('foobar')
    subject.client.channel << [:file_list, {:nick => 'foobar'}]
  end

  describe "when browsing an actual nick" do
    before :each do
      subject.client.should_receive(:parsed_file_list).and_yield(
        LibXML::XML::Document.string <<-XML.strip_heredoc
          <?xml version="1.0" encoding="UTF-8"?>
          <FileListing Base="/" Version="1" Generator="fargo">
            <Directory Name="shared">
              <File Name="a" Size="1" TTH="atth"/>
              <File Name="b" Size="1" TTH="btth"/>
              <Directory Name="c">
                <File Name="d" Size="1" TTH="dtth"/>
              </Directory>
            </Directory>
          </FileListing>
        XML
      )
      capture(:stdout) {
        subject.client.channel << [:file_list, {:nick => 'foobar'}]
      }
    end

    it "beings at the root" do
      capture(:stdout) { subject.pwd }.should == "/\n"
    end

    it "lists contents correctly" do
      capture(:stdout) { subject.ls }.should == "shared/\n"
      capture(:stdout) { subject.cd 'shared' }
      output = capture(:stdout) { subject.ls }
      output.should =~ /a\n/
      output.should =~ /b\n/
      output.should =~ /c\/\n/
    end

    it "lists contents correctly" do
      capture(:stdout) { subject.ls }.should == "shared/\n"
      output = capture(:stdout) { subject.ls 'shared' }
      output.should =~ /a\n/
      output.should =~ /b\n/
      output.should =~ /c\/\n/

      capture(:stdout) { subject.cd 'shared' }
      output = capture(:stdout) { subject.ls }
      output.should =~ /a\n/
      output.should =~ /b\n/
      output.should =~ /c\/\n/

      capture(:stdout) { subject.cd 'c' }
      capture(:stdout) { subject.ls }.should =~ /d\n/
    end

    it "moves around the pseudo-filesystem correctly" do
      capture(:stdout) { subject.pwd }.should == "/\n"
      capture(:stdout) { subject.cd 'shared' }
      capture(:stdout) { subject.pwd }.should == "/shared\n"
      capture(:stdout) { subject.cd 'c' }
      capture(:stdout) { subject.pwd }.should == "/shared/c\n"
      capture(:stdout) { subject.cd }
      capture(:stdout) { subject.pwd }.should == "/\n"
      capture(:stdout) { subject.cd 'shared/../shared/c'}
      capture(:stdout) { subject.pwd }.should == "/shared/c\n"
    end

    it "asks the client to download files correctly" do
      subject.client.should_receive(:download).with(
        'foobar', 'shared/a', 'atth', 1)
      capture(:stdout) { subject.download 'shared/a' }

      subject.client.should_receive(:download).with(
        'foobar', 'shared/c/d', 'dtth', 1)
      capture(:stdout) {
        subject.cd 'shared'
        subject.download '../shared/c/d'
      }
    end

    it "completes files correctly" do
      subject.send(:completion, false).should =~ ['shared/', '..']
      subject.send(:completion, true).should =~ ['shared/', '..']

      capture(:stdout) { subject.cd 'shared' }
      subject.send(:completion, false).should =~ ['c/', '..']
      subject.send(:completion, true).should =~ ['a', 'b', 'c/', '..']
    end

  end

end
