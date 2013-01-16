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

  #
  # sending events as a post parameter named 'json'
  # e.g. curl -XPOST 'http://127.0.0.1:9911/tag1' -d'time=1357860203&json=[{"a":1}]'
  #
  def test_parameter
    d = create_driver

    time = Time.parse("2013-01-10 23:23:23 UTC").to_i

    d.expect_emit "tag1", time, {"a"=>1}
    d.expect_emit "tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        res = post_as_parameter("/#{tag}", time.to_s, [record].to_json)
        assert_equal "200", res.code
      }
    end
  end

  #
  # sending evens as a request body (application/json)
  # e.g. curl -XPOST 'http://127.0.0.1:9911/tag1?time=1357860203' -d'[{"a":1}]' -H 'Content-Type:application/json; charset=utf-8'
  #
  def test_application_json
    d = create_driver

    time = Time.parse("2013-01-10 23:23:23 UTC").to_i

    d.expect_emit "tag1", time, {"a"=>1}
    d.expect_emit "tag2", time, {"a"=>2}

    d.run do
      d.expected_emits.each {|tag,time,record|
        res = post_as_application_json("/#{tag}", time.to_s, [record].to_json)
        assert_equal "200", res.code
      }
    end
  end

  def test_multiple_events_as_parameter
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
        res = post_as_parameter("/#{tag}", time, events.to_json)
        assert_equal "200", res.code
      }
    end
  end

  def test_multiple_events_as_application_json
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
        res = post_as_application_json("/#{tag}", time.to_s, events.to_json)
        assert_equal "200", res.code
      }
    end
  end

  def test_zero_events_as_parameter
    # An empty event list should not fail
    d = create_driver
    time = Time.parse("2013-01-10 23:23:23 UTC").to_i
    d.run do
      res = post_as_parameter("/zero", time.to_s, [].to_json)
      assert_equal "200", res.code
    end
  end

  def test_zero_events_as_application_json
    # An empty event list should not fail
    d = create_driver
    time = Time.parse("2013-01-10 23:23:23 UTC").to_i
    d.run do
      res = post_as_application_json("/zero", time.to_s, [].to_json)
      assert_equal "200", res.code
    end
  end

  private

  def post_as_parameter(path, time, json)
    http = Net::HTTP.new("127.0.0.1", 9911)
    req = Net::HTTP::Post.new(path, {})
    req.set_form_data({"time" => time, "json" => json})
    http.request(req)
  end

  def post_as_application_json(path, time, json)
    http = Net::HTTP.new("127.0.0.1", 9911)
    req = Net::HTTP::Post.new("#{path}?time=#{time.to_s}", {"content-type"=>"application/json; charset=utf-8"})
    req.body = json
    http.request(req)
  end

end

