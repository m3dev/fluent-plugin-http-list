module Fluent

class HttpListInput < Input
  Plugin.register_input('http_list', self)

  include DetachMultiProcessMixin

  require 'http/parser'

  def initialize
    require 'webrick/httputils'
    super
  end

  config_param :port, :integer, :default => 9880
  config_param :bind, :string, :default => '0.0.0.0'
  config_param :body_size_limit, :size, :default => 32*1024*1024 
  config_param :keepalive_timeout, :time, :default => 10   
  config_param :blob_fallback, :bool, :default => false
  config_param :fallback_delimiter, :string, :default => "\n"
  config_param :default_tag, :string, :default => nil
  config_param :record_remote_host, :bool, :default => false
  config_param :remote_address_key, :string, :default => "remote_addr"
  config_param :remote_address_dns_key, :string, :default => "host"

  def configure(conf)
    super
  end

  class KeepaliveManager < Coolio::TimerWatcher
    class TimerValue
      def initialize
        @value = 0
      end
      attr_accessor :value
    end

    def initialize(timeout)
      super(1, true)
      @cons = {}
      @timeout = timeout.to_i
    end

    def add(sock)
      @cons[sock] = sock
    end

    def delete(sock)
      @cons.delete(sock)
    end

    def on_timer
      @cons.each_pair {|sock,val|
        if sock.step_idle > @timeout
          sock.close
        end
      }
    end
  end

  def start
    $log.debug "listening for http on #{@bind}:#{@port}"
    lsock = TCPServer.new(@bind, @port)

    detach_multi_process do
      super
      @km = KeepaliveManager.new(@keepalive_timeout)
      @lsock = Coolio::TCPServer.new(lsock, nil, Handler, @km, method(:on_request), @body_size_limit)

      @loop = Coolio::Loop.new
      @loop.attach(@km)
      @loop.attach(@lsock)

      @thread = Thread.new(&method(:run))
    end
  end

  def shutdown
    @loop.watchers.each {|w| w.detach }
    @loop.stop
    @lsock.close
    @thread.join
  end

  def run
    @loop.run
  rescue
    $log.error "unexpected error", :error=>$!.to_s
    $log.error_backtrace
  end

  def on_request(path_info, params)
    begin
      path = path_info[1..-1]  # remove /
      tag = path.split('/').join('.')

      if tag.strip.empty? and @default_tag
        tag = @default_tag
      end

      if js = params['json']
        records = JSON.parse(js)
        p records
      elsif @blob_fallback
        records = params['body'].to_s.
          split(@fallback_delimiter).
          map {|r| JSON.parse({"message" => r.encode('UTF-8', {:invalid => :replace, :undef => :replace, :replace => '?'})}.to_json)}
      else
        raise "'json' parameter is required" + params.keys.to_s
      end

    time = params['time'].nil? ? Engine.now : params['time'].to_i

    rescue
      return ["400 Bad Request", {'Content-type'=>'text/plain'}, "400 Bad Request\n#{$!}\n"]
    end


    begin
      records.each{|r| 
          if @record_remote_host
            r.update({@remote_address_key     => params['remote_address'].to_s,
                      @remote_address_dns_key => params['remote_address_dns'].to_s})
          end
          Engine.emit(tag, time, r)
      }
    rescue
      return ["500 Internal Server Error", {'Content-type'=>'text/plain'}, "500 Internal Server Error\n#{$!}\n"]
    end

    return ["200 OK", {'Content-type'=>'text/plain'}, ""]
  end

  class Handler < Coolio::Socket
    def initialize(io, km, callback, body_size_limit)
      super(io)
      @remote_address = io.remote_address.ip_address
      @remote_address_dns = io.remote_address.getnameinfo[0]
      @km = km
      @callback = callback
      @body_size_limit = body_size_limit
      @content_type = ""
      @next_close = false

      @idle = 0
      @km.add(self)
    end

    def step_idle
      @idle += 1
    end

    def on_close
      @km.delete(self)
    end

    def on_connect
      @parser = Http::Parser.new(self)
    end

    def on_read(data)
      @idle = 0
      @parser << data
    rescue
      $log.warn "unexpected error", :error=>$!.to_s
      $log.warn_backtrace
      close
    end

    def on_message_begin
      @body = ''
    end

    def on_headers_complete(headers)
      expect = nil
      size = nil
      if @parser.http_version == [1, 1]
        #Modified to always be false - Paul McCann 2012/10/24
        #Changed because it was likely cause of slowness in production
        @keep_alive = false
      else
        @keep_alive = false
      end
      headers.each_pair {|k,v|
        case k
        when /Expect/i
          expect = v
        when /Content-Length/i
          size = v.to_i
        when /Content-Type/i
          @content_type = v
        when /Connection/i
          if v =~ /close/i
            @keep_alive = false
          elsif v =~ /Keep-alive/i
            @keep_alive = true
          end
        end
      }
      if expect
        if expect == '100-continue'
          if !size || size < @body_size_limit
            send_response_nobody("100 Continue", {})
          else
            send_response_and_close("413 Request Entity Too Large", {}, "Too large")
          end
        else
          send_response_and_close("417 Expectation Failed", {}, "")
        end
      end
    end

    def on_body(chunk)
      if @body.bytesize + chunk.bytesize > @body_size_limit
        unless closing?
          send_response_and_close("413 Request Entity Too Large", {}, "Too large")
        end
        return
      end
      @body << chunk
    end

    def on_message_complete
      return if closing?

      params = WEBrick::HTTPUtils.parse_query(@parser.query_string)

      if @content_type =~ /^application\/x-www-form-urlencoded/
        params.update WEBrick::HTTPUtils.parse_query(@body)
      elsif @content_type =~ /^multipart\/form-data; boundary=(.+)/
        boundary = WEBrick::HTTPUtils.dequote($1)
        params.update WEBrick::HTTPUtils.parse_form_data(@body, boundary)
      elsif @content_type =~ /^application\/json/
        params['json'] = @body
      end
      path_info = @parser.request_path

      params['body'] = @body
      params['remote_address'] = @remote_address
      params['remote_address_dns'] = @remote_address_dns

      code, header, body = *@callback.call(path_info, params)
      body = body.to_s

      if @keep_alive
        header['Connection'] = 'Keep-Alive'
        send_response(code, header, body)
      else
        send_response_and_close(code, header, body)
      end
    end

    def on_write_complete
      close if @next_close
    end

    def send_response_and_close(code, header, body)
      send_response(code, header, body)
      @next_close = true
    end

    def closing?
      @next_close
    end

    def send_response(code, header, body)
      header['Content-length'] ||= body.bytesize
      header['Content-type'] ||= 'text/plain'

      data = %[HTTP/1.1 #{code}\r\n]
      header.each_pair {|k,v|
        data << "#{k}: #{v}\r\n"
      }
      data << "\r\n"
      write data

      write body
    end

    def send_response_nobody(code, header)
      data = %[HTTP/1.1 #{code}\r\n]
      header.each_pair {|k,v|
        data << "#{k}: #{v}\r\n"
      }
      data << "\r\n"
      write data
    end
  end
end


end

