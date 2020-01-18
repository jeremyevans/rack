# frozen_string_literal: true

require 'rack/utils'

module Rack

  # Middleware that applies chunked transfer encoding to response bodies
  # when the response does not include a Content-Length header.
  class Chunked
    include Rack::Utils

    # A body wrapper that emits chunked responses
    class Body
      TERM = "\r\n"
      TAIL = "0#{TERM}"

      include Rack::Utils

      def initialize(body)
        @body = body
      end

      def each(&block)
        term = TERM
        @body.each do |chunk|
          size = chunk.bytesize
          next if size == 0

          chunk = chunk.b
          yield [size.to_s(16), term, chunk, term].join
        end
        yield TAIL
        insert_trailers(&block)
        yield TERM
      end

      def close
        @body.close if @body.respond_to?(:close)
      end

      private

      def insert_trailers(&block)
      end
    end

    class TrailerBody < Body
      private

      def insert_trailers(&block)
        @body.trailers.each_pair do |k, v|
          yield "#{k}: #{v}\r\n"
        end
      end
    end

    def initialize(app)
      @app = app
    end

    # pre-HTTP/1.0 (informally "HTTP/0.9") HTTP requests did not have
    # a version (nor response headers)
    def chunkable_version?(ver)
      case ver
      when 'HTTP/1.0', nil, 'HTTP/0.9'
        false
      else
        true
      end
    end

    def call(env)
      status, headers, body = @app.call(env)

      if ! chunkable_version?(env[SERVER_PROTOCOL]) ||
         STATUS_WITH_NO_ENTITY_BODY.key?(status.to_i) ||
         Utils.indifferent(headers, CONTENT_LENGTH) ||
         Utils.indifferent(headers, TRANSFER_ENCODING)
        [status, headers, body]
      else
        Utils.indifferent_delete(headers, CONTENT_LENGTH)
        headers[TRANSFER_ENCODING] = 'chunked'
        if Utils.indifferent(headers, 'Trailer')
          [status, headers, TrailerBody.new(body)]
        else
          [status, headers, Body.new(body)]
        end
      end
    end
  end
end
