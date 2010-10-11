require 'spec_helper'

describe Fargo::Supports::LocalFileList, :type => :emsync do

  before :each do
    @root = Fargo.config.download_dir + '/shared'
    FileUtils.mkdir_p @root
    File.open(@root + '/a', 'w'){ |f| f << 'a' }
    File.open(@root + '/b', 'w'){ |f| f << 'c' }
    FileUtils.mkdir @root + '/c'
    File.open(@root + '/c/d', 'w'){ |f| f << 'd' }

    @client = Fargo::Client.new
    @client.config.override_share_size = nil
  end

  it "maintains a list of local files, recursively searching folders" do
    @client.share_directory @root

    hash = @client.local_file_list
    hash['shared'].should be_a(Hash)
    hash['shared']['a'].should be_a(Fargo::Listing)
    hash['shared']['b'].should be_a(Fargo::Listing)
    hash['shared']['c'].should be_a(Hash)
    hash['shared']['c']['d'].should be_a(Fargo::Listing)

    hash['shared']['a'].name.should == 'shared/a'
    hash['shared']['b'].name.should == 'shared/b'
    hash['shared']['c']['d'].name.should == 'shared/c/d'
  end

  it "caches the file list so that another client can come along" do
    @client.share_directory @root

    client2 = Fargo::Client.new
    client2.config.override_share_size = nil
    client2.local_file_list.should     == @client.local_file_list
    client2.share_size.should          == @client.share_size
    client2.shared_directories.should  == @client.shared_directories
  end

  it "caches the size of each file shared" do
    @client.share_directory @root

    @client.share_size.should == 3 # 3 bytes, one in each file
  end

  it "allows overwriting the published share size just for fun" do
    @client.config.override_share_size = 100

    @client.share_size.should == 100
  end

  it "correctly creates an array of listings that it's sharing" do
    @client.share_directory @root

    listings = @client.local_listings

    listings.size.should == 3

    listings.shift.name.should == 'shared/a'
    listings.shift.name.should == 'shared/b'
    listings.shift.name.should == 'shared/c/d'
  end

  it "finds listings correctly when given their name" do
    @client.share_directory @root

    ret_val = @client.listing_for 'shared/a'
    ret_val.should be_a(Fargo::Listing)
    ret_val.name.should == 'shared/a'
  end

  it "also finds listings based on their TTH value" do
    @client.share_directory @root
    listing = @client.local_listings[0]

    @client.listing_for('TTH/' + listing.tth).should == listing
  end
end
