require 'helper'

describe SPDY::Parser do
  let(:s) { SPDY::Parser.new }

  context "callbacks" do
    it "should accept header callback" do
      lambda do
        s.on_headers {}
      end.should_not raise_error
    end

    it "should accept body callback" do
      lambda do
        s.on_body {}
      end.should_not raise_error
    end

    it "should accept message complete callback" do
      lambda do
        s.on_message_complete {}
      end.should_not raise_error
    end
  end

  it "should accept incoming data" do
    lambda { s << DATA }.should_not raise_error
  end

  it "should reassemble broken packets" do
    stream, data = nil
    s.on_body { |stream_id, d| stream, data = stream_id, d }

    lambda { s << DATA[0...DATA.size - 10] }.should_not raise_error
    lambda { s << DATA[DATA.size-10..DATA.size] }.should_not raise_error

    stream.should == 1
    data.should == 'This is SPDY.'

    fired = false
    s.on_open { fired = true }
    s << SYN_STREAM

    fired.should be_true
  end

  it "should parse multiple frames in a single buffer" do
    fired = 0
    s.on_body { |stream_id, d| fired += 1 }
    s << DATA*2
    fired.should == 2
  end

  context "CONTROL" do
    it "should parse SYN_STREAM packet" do
      fired = false
      s.on_open { fired = true }
      s << SYN_STREAM

      fired.should be_true
    end

    it "should return parsed headers for SYN_STREAM" do
      sid, sid2, asid, pri, headers = nil
      order = []
      s.on_open do |stream, astream, priority|
        order << :open
        sid = stream; asid = astream; pri = priority;
      end
      
      s.on_headers do |stream, head|
        order << :headers
        sid2 = stream;  headers = head
      end

      s << SYN_STREAM

      order.should == [:open, :headers]
      
      sid.class.should == Fixnum
      sid.should == 1
      sid2.should == 1
      asid.should == 0
      pri.should == 0

      headers.class.should == Hash
      headers['version'].should == "HTTP/1.1"
    end
    
    it "should not fire the on_open callback for SYN_REPLY" do
      failed = false
      s.on_open { failed = true }
      s << SYN_REPLY

      failed.should be_false
    end
    
    it "should return parsed headers for SYN_REPLY" do
      sid, headers = nil
      s.on_headers do |stream, head|
        sid = stream;  headers = head
      end

      s << SYN_REPLY

      sid.should == 1
      
      headers.class.should == Hash
      headers['version'].should == "HTTP/1.1"
    end
    
    it "should parse PING packet" do
      fired = false
      s.on_ping { |num| fired = num }
      s << PING

      fired.should == 1
    end

    it "should parse HEADERS packet" do
      fired = false
      s.on_headers { fired = true }
      s << HEADERS

      fired.should be_true
    end

    it "should return parsed headers for HEADERS" do
      sid, headers = nil
      s.on_headers do |stream, head|
        sid = stream; headers = head
      end

      s << HEADERS

      sid.should == 1

      headers.class.should == Hash
      headers['version'].should == "HTTP/1.1"
    end

    it "should parse SETTINGS packet" do
      fired = false
      s.on_settings { fired = true }
      s << SETTINGS

      fired.should be_true
    end
  end

  context "DATA" do
    it "should parse data packet" do
      stream, data = nil
      s.on_body { |stream_id, d| stream, data = stream_id, d }
      s << DATA

      stream.should == 1
      data.should == 'This is SPDY.'
    end
  end
  
  context "RST_STREAM" do
    it "should parse RST_STREAM packet" do
      stream, status = nil
      s.on_reset { |stream_id, s| stream, status = stream_id, s }
      s << RST_STREAM

      stream.should == 1
      status.should == 1
    end
  end

  context "FIN" do
    it "should invoke message_complete on FIN flag in CONTROL packet" do
      f1, f2 = false
      s.on_open { f1 = true }
      s.on_message_complete { |s| f2 = s }

      sr = SPDY::Protocol::Control::SynStream.new
      sr.header.stream_id = 3
      sr.header.type  = 1
      sr.header.flags = 0x01
      sr.header.len = 10

      s << sr.to_binary_s

      f1.should be_true
      f2.should == 3
    end

    it "should invoke message_complete on FIN flag in DATA packet" do
      f1, f2 = false
      s.on_body { f1 = true }
      s.on_message_complete { |s| f2 = s }

      s << DATA_FIN

      f1.should be_true
      f2.should == 1
    end

  end

end
