require 'spec_helper'

describe Fargo::Supports::LocalFileList, :type => :emsync do
  subject { Fargo::Client.new }
  let(:root) { Fargo.config.download_dir + '/shared' }

  include Fargo::TTH

  before :each do
    FileUtils.mkdir_p root
    File.open(root + '/a', 'w'){ |f| f << 'a' }
    File.open(root + '/b', 'w'){ |f| f << 'c' }
    FileUtils.mkdir root + '/c'
    File.open(root + '/c/d', 'w'){ |f| f << 'd' }

    subject.config.override_share_size = nil
  end

  it "maintains a list of local files, recursively searching folders" do
    subject.share_directory root

    hash = subject.local_file_list
    hash['shared'].should be_a(Hash)
    hash['shared']['a'].should be_a(Fargo::Listing)
    hash['shared']['b'].should be_a(Fargo::Listing)
    hash['shared']['c'].should be_a(Hash)
    hash['shared']['c']['d'].should be_a(Fargo::Listing)

    hash['shared']['a'].name.should == 'shared/a'
    hash['shared']['b'].name.should == 'shared/b'
    hash['shared']['c']['d'].name.should == 'shared/c/d'
  end

  it "caches the file list so that another subject can come along" do
    subject.share_directory root

    other = Fargo::Client.new
    other.config.override_share_size = nil
    other.local_file_list.should     == subject.local_file_list
    other.share_size.should          == subject.share_size
    other.shared_directories.should  == subject.shared_directories
  end

  it "caches the size of each file shared" do
    subject.share_directory root

    subject.share_size.should == 3 # 3 bytes, one in each file
  end

  it "allows overwriting the published share size just for fun" do
    subject.config.override_share_size = 100

    subject.share_size.should == 100
  end

  it "correctly creates an array of listings that it's sharing" do
    subject.share_directory root

    listings = subject.local_listings

    listings.size.should == 3

    listings.shift.name.should == 'shared/a'
    listings.shift.name.should == 'shared/b'
    listings.shift.name.should == 'shared/c/d'
  end

  it "finds listings correctly when given their name" do
    subject.share_directory root

    ret_val = subject.listing_for 'shared/a'
    ret_val.should be_a(Fargo::Listing)
    ret_val.name.should == 'shared/a'
  end

  it "also finds listings based on their TTH value" do
    subject.share_directory root
    listing = subject.local_listings[0]

    subject.listing_for('TTH/' + listing.tth).should == listing
  end

  it "generates a correct file list" do
    subject.share_directory root
    file = Bzip2::Reader.open(subject.config.config_dir + '/files.xml.bz2')
    xml = file.read

    xml.should == <<-XML
<?xml version="1.0" encoding="utf-8"?>
<FileListing Base="/" Version="1" Generator="fargo #{Fargo::VERSION}">
  <Directory Name="shared">
    <File Name="a" Size="1" TTH="#{file_tth(root + '/a')}"/>
    <File Name="b" Size="1" TTH="#{file_tth(root + '/b')}"/>
    <Directory Name="c">
      <File Name="d" Size="1" TTH="#{file_tth(root + '/c/d')}"/>
    </Directory>
  </Directory>
</FileListing>
XML
  end
end
