require 'fluent/test'
require 'net/http'

class HttpListInputTest < Test::Unit::TestCase
  def setup
    Fluent::Test.setup
    require 'fluent/plugin/in_http_list'
  end

  CONFIG = %[
    port 9911
    bind 127.0.0.1
    body_size_limit 10m
    keepalive_timeout 5
  ]

  def create_driver(conf=CONFIG)
    Fluent::Test::InputTestDriver.new(Fluent::HttpListInput).configure(conf)
  end

  def test_configure
    d = create_driver
    assert_equal 9911, d.instance.port
    assert_equal '127.0.0.1', d.instance.bind
    assert_equal 10*1024*1024, d.instance.body_size_limit
    assert_equal 5, d.instance.keepalive_timeout
  end

  def test_json
    d = create_driver

    time = Time.parse("2013-01-10 23:23:23 UTC").to_i

    d.expect_emit "tag1", time, {"a"=>1}
    d.expect_emit "tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        res = post("/#{tag}", {"json"=>[record].to_json, "time"=>time.to_s})
        assert_equal "200", res.code
      }
    end
  end

  def test_application_json
    d = create_driver
    
    time = Time.parse("2013-01-10 23:23:23 UTC").to_i

    d.expect_emit "tag1", time, {"a"=>1}
    d.expect_emit "tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        http = Net::HTTP.new("127.0.0.1", 9911)
        req = Net::HTTP::Post.new("/#{tag}?time=#{time.to_s}", {"content-type"=>"application/json; charset=utf-8"})
        req.body = [record].to_json
        res = http.request(req)
        assert_equal "200", res.code
      }
    end
  end

  def test_multiple_events
    d = create_driver

    time = Time.parse("2013-01-10 23:23:23 UTC").to_i

    d.expect_emit "tag1", time, {"a"=>1}
    d.expect_emit "tag1", time, {"a"=>2}
    d.expect_emit "tag1", time, {"a"=>3}
    d.expect_emit "tag2", time, {"a"=>4}
    d.expect_emit "tag2", time, {"a"=>5}
    d.expect_emit "tag2", time, {"a"=>6}

    test_events = [
        ["tag1", (1..3).to_a.collect {|x| {"a"=>x}}],
        ["tag2", (4..6).to_a.collect {|x| {"a"=>x}}]
    ]

    d.run do
      test_events.each {|tag, events|
        http = Net::HTTP.new("127.0.0.1", 9911)
        req = Net::HTTP::Post.new("/#{tag}?time=#{time.to_s}", {"content-type"=>"application/json; charset=utf-8"})
        req.body = events.to_json
        res = http.request(req)
        assert_equal "200", res.code
      }
    end
  end
 
  def test_zero_events
    # An empty event list should not fail
    d = create_driver

    tag = 'zero'

    d.run do
    http = Net::HTTP.new("127.0.0.1", 9911)
    req = Net::HTTP::Post.new("/#{tag}", {"content-type"=>"application/json; charset=utf-8"})
    req.body = [].to_json
    res = http.request(req)
    assert_equal "200", res.code
    end
  end
 
  def post(path, params)
    http = Net::HTTP.new("127.0.0.1", 9911)
    req = Net::HTTP::Post.new(path, {})
    req.set_form_data(params)
    http.request(req)
  end
end

