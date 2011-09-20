require 'spec_helper'
require 'active_support/core_ext/string/strip'

describe Fargo::Supports::LocalFileList, :type => :emsync do
  subject { Fargo::Client.new }
  let(:root) { Fargo.config.download_dir + '/shared' }
  let(:root2) { Fargo.config.download_dir + '/shared2' }

  include Fargo::TTH

  before :each do
    FileUtils.mkdir_p root
    FileUtils.mkdir_p root2
    File.open(root + '/a', 'w'){ |f| f << 'a' }
    File.open(root2 + '/a', 'w'){ |f| f << 'a' }
    File.open(root + '/b', 'w'){ |f| f << 'c' }
    FileUtils.mkdir root + '/c'
    File.open(root + '/c/d', 'w'){ |f| f << 'd' }

    Fargo.config.override_share_size = nil
  end

  after :each do
    FileUtils.rm_rf root
  end

  it "maintains a list of local files, recursively searching folders" do
    subject.share_directory root

    subject.listing_for('shared').should be_nil
    subject.listing_for('shared/a').should be_a(Fargo::Listing)
    subject.listing_for('shared/b').should be_a(Fargo::Listing)
    subject.listing_for('shared/c').should be_nil
    subject.listing_for('shared/c/d').should be_a(Fargo::Listing)
  end

  it "caches the file list so that another subject can come along" do
    subject.share_directory root

    other = Fargo::Client.new
    other.config.override_share_size = nil
    other.share_size.should          == subject.share_size
    other.shared_directories.should  == subject.shared_directories
  end

  it "allows shared directories in the global configuration" do
    Fargo.config.shared_directories = [root]

    subject.shared_directories.should =~ [Pathname.new(root)]
  end

  it "caches the size of each file shared" do
    subject.share_directory root

    subject.share_size.should == 3 # 3 bytes, one in each file
  end

  it "allows overwriting the published share size just for fun" do
    subject.config.override_share_size = 100

    subject.share_size.should == 100
  end

  it "finds listings correctly when given their name" do
    subject.share_directory root

    ret_val = subject.listing_for 'shared/a'
    ret_val.should be_a(Fargo::Listing)
    ret_val.path.should == root + '/a'

    subject.share_directory root2
    subject.listing_for('shared/a').path.should == root + '/a'
    subject.listing_for('shared2/a').path.should == root2 + '/a'
  end

  it "also finds listings based on their TTH value" do
    subject.share_directory root
    tth = file_tth(root + '/a')
    listing = subject.listing_for('TTH/' + tth)
    listing.should be_a(Fargo::Listing)
    listing.path.should == root + '/a'
    listing.tth.should == tth
  end

  it "generates a correct file list" do
    SecureRandom.stub(:hex).and_return('CID')
    subject.share_directory root
    file = Bzip2::Reader.open(subject.config.config_dir + '/files.xml.bz2')
    xml  = LibXML::XML::Document.io(file)
    file.close

    expected = LibXML::XML::Document.string <<-XML.strip_heredoc
      <?xml version="1.0" encoding="UTF-8"?>
      <FileListing Base="/" Version="1" Generator="fargo V:#{Fargo::VERSION}"
                   CID="CID">
        <Directory Name="shared">
          <File Name="a" Size="1" TTH="#{file_tth(root + '/a')}"/>
          <File Name="b" Size="1" TTH="#{file_tth(root + '/b')}"/>
          <Directory Name="c">
            <File Name="d" Size="1" TTH="#{file_tth(root + '/c/d')}"/>
          </Directory>
        </Directory>
      </FileListing>
    XML

    xml.canonicalize.should == expected.canonicalize
  end

  it "searches for files correctly" do
    subject.share_directory root
    listings = subject.search_local_listings Fargo::Search.new(:query => 'b')
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/b'), 1, 'shared/b')
    ]

    listings = subject.search_local_listings Fargo::Search.new(:query => 'd')
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/c/d'), 1, 'shared/c/d'),
      Fargo::Listing.new(nil, nil, 'shared')
    ]

    listings = subject.search_local_listings Fargo::Search.new(:query => 'shar')
    listings.should =~ [
      Fargo::Listing.new(nil, nil, 'shared')
    ]
  end

  it "searches for files case insensitively" do
    subject.share_directory root
    listings = subject.search_local_listings Fargo::Search.new(:query => 'B')
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/b'), 1, 'shared/b')
    ]
  end

  it "ignores dotfiles" do
    File.open(root + '/.z', 'w'){ |f| f << 'a' }
    subject.share_directory root
    listings = subject.search_local_listings Fargo::Search.new(:query => '.z')
    listings.should =~ []
  end

  it "searches for apostrophers and quotes" do
    File.open(root + '/a\'s', 'w'){ |f| f << 'a' }
    File.open(root + '/"', 'w'){ |f| f << 'c' }
    subject.share_directory root
    listings = subject.search_local_listings Fargo::Search.new(:query => "'")
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/a\'s'), 1, 'shared/a\'s')
    ]

    listings = subject.search_local_listings Fargo::Search.new(:query => '"')
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/"'), 1, 'shared/"')
    ]

    listings = subject.search_local_listings Fargo::Search.new(:query => 'a\'s')
    listings.should =~ [
      Fargo::Listing.new(file_tth(root + '/a\'s'), 1, 'shared/a\'s')
    ]
  end

  describe "updating the local file list" do

    before do
      subject.share_directory root
      File.delete(root + '/a')
    end

    shared_examples_for 'an updated file list' do
      its(:share_size) { should == 2 }
      it "removes deleted files" do
        subject.listing_for('shared/a').should be_nil
      end
    end

    context "re-sharing directories" do
      it_should_behave_like 'an updated file list' do
        before do
          subject.share_directory root
        end
      end
    end

    context "scheduled updates running" do
      it_should_behave_like 'an updated file list' do
        before do
          EventMachine::Timer.should_receive(:new).with(60) { |time, blk|
            # Make sure we recursively schedule another update
            subject.should_receive(:schedule_update)
            blk.call
          }

          subject.send(:schedule_update)
        end
      end
    end

  end
end
