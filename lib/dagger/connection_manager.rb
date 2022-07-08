module Dagger

  class ConnectionManager

    def initialize(opts = {})
      @opts = opts
      @active_connections = {}
      @mutex = Mutex.new
    end

    def shutdown
      @mutex.synchronize do
        # puts "Shutting down connections: #{@active_connections.count}"
        @active_connections.each do |_, connection|
          connection.finish
        end
        @active_connections = {}
      end
    end

    # Gets a connection for a given URI. This is for internal use only as it's
    # subject to change (we've moved between HTTP client schemes in the past
    # and may do it again).
    #
    # `uri` is expected to be a string.
    def connection_for(uri)
      @mutex.synchronize do
        connection = @active_connections[[uri.host, uri.port]]

        if connection.nil?
          connection = Dagger::Client.init_connection(uri, @opts)
          connection.start

          @active_connections[[uri.host, uri.port]] = connection
          # puts "#{@active_connections.count} connections"
        end

        connection
      end
    end

    # Executes an HTTP request to the given URI with the given method. Also
    # allows a request body, headers, and query string to be specified.
    def send_request(uri, request)
      connection = connection_for(uri)
      @mutex.synchronize do
        begin
          connection.request(request)
        rescue StandardError => err
          err
        end
      end.tap do |result|
        raise(result) if result.is_a?(StandardError)
      end
    end

  end

end