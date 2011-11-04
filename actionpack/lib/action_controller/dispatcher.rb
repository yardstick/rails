module ActionController
  # Dispatches requests to the appropriate controller and takes care of
  # reloading the app after each request when Dependencies.load? is true.
  class Dispatcher
    @@guard = Mutex.new

    class << self
      def define_dispatcher_callbacks(cache_classes)
        unless cache_classes
          # Development mode callbacks
          before_dispatch :reload_application
          after_dispatch :cleanup_application

          ActionView::Helpers::AssetTagHelper.cache_asset_timestamps = false
        end

        # Common callbacks
        to_prepare :load_application_controller do
          begin
            require_dependency 'application' unless defined?(::ApplicationController)
          rescue LoadError => error
            raise unless error.message =~ /application\.rb/
          end
        end

        if defined?(ActiveRecord)
          after_dispatch :checkin_connections
          to_prepare(:activerecord_instantiate_observers) { ActiveRecord::Base.instantiate_observers }
        end

        after_dispatch :flush_logger if Base.logger && Base.logger.respond_to?(:flush)

        to_prepare do
          I18n.reload!
        end
      end

      # Backward-compatible class method takes CGI-specific args. Deprecated
      # in favor of Dispatcher.new(output, request, response).dispatch.
      def dispatch(cgi = nil, session_options = CgiRequest::DEFAULT_SESSION_OPTIONS, output = $stdout)
        new(output).dispatch_cgi(cgi, session_options)
      end

      # Add a preparation callback. Preparation callbacks are run before every
      # request in development mode, and before the first request in production
      # mode.
      #
      # An optional identifier may be supplied for the callback. If provided,
      # to_prepare may be called again with the same identifier to replace the
      # existing callback. Passing an identifier is a suggested practice if the
      # code adding a preparation block may be reloaded.
      def to_prepare(identifier = nil, &block)
        @prepare_dispatch_callbacks ||= ActiveSupport::Callbacks::CallbackChain.new
        callback = ActiveSupport::Callbacks::Callback.new(:prepare_dispatch, block, :identifier => identifier)
        @prepare_dispatch_callbacks.replace_or_append!(callback)
      end

      # If the block raises, send status code as a last-ditch response.
      # !!! hacked because script/unicorn_dev seems to send its own 500 response regardless of what we do here.
      def failsafe_response(fallback_output, status, originating_exception = nil, request = nil, response = nil)
        yield
      rescue Exception => exception
        begin
          log_failsafe_exception(status, exception)
          status, ctype, body = failsafe_response_body(request, response, status)
          ctype ||= 'text/html'
          fallback_output.write body

          # Ensure unicorn knows what status and content-type we're rollin
          response.headers['status'] = status.to_s[0..2]
          response.headers['Status'] = status
          response.headers['type'] = response.headers['Content-Type'] = ctype
          response.headers['Content-Length'] ||= body.size.to_s
          response.request ||= request
          response.prepare!
          response.out(fallback_output)
          nil
        rescue Exception => failsafe_error # Logger or IO errors
          $stderr.puts "Error during failsafe response: #{failsafe_error}"
          $stderr.puts "(originally #{originating_exception})" if originating_exception
        end
      end

      private

        # Builds a response body and status from a failsafe exception.
        # Attempts to get the content type from the request to craft a better
        # response.
        #
        # request - Request instance, if available.
        # status  - HTTP Status string, defaults to "500 Internal Server Error"
        #
        # Returns an Array with [status, body] (two strings).
        def failsafe_response_body(request, response, status)
          headers = request.respond_to?(:headers) ? request.headers : {}
          ctype   = headers['CONTENT_TYPE'].to_s.split(";", 2).first.to_s
          msg     = "Bad Request.  Could not parse request body sent as #{ctype}"
          case ctype
            when ""
            when /json/i
              ctype = 'application/json'
              return [BAD_REQUEST, ctype, %({"error":#{msg.inspect}})]
            when /xml/i
              ctype = 'application/xml'
              return [BAD_REQUEST, ctype, %(<error><message>#{msg}</message></error>)]
            when /ya?ml/i
              ctype = 'application/x-yaml'
              return [BAD_REQUEST, ctype, %(--- \nerror: #{msg.inspect})]
          end

          error_path = "#{error_file_path}/#{status.to_s[0..3]}.html"

          if File.exist?(error_path)
            [status, nil, File.read(error_path)]
          else
            [status, nil, "<html><body><h1>#{status}</h1></body></html>"]
          end
        end

        def log_failsafe_exception(status, exception)
          message = "/!\\ FAILSAFE /!\\  #{Time.now}\n  Status: #{status}\n"
          message << "  #{exception}\n    #{exception.backtrace.join("\n    ")}" if exception
          failsafe_logger.fatal message
        end

        def failsafe_logger
          if defined?(::RAILS_DEFAULT_LOGGER) && !::RAILS_DEFAULT_LOGGER.nil?
            ::RAILS_DEFAULT_LOGGER
          else
            Logger.new($stderr)
          end
        end
    end

    cattr_accessor :error_file_path
    self.error_file_path = Rails.public_path if defined?(Rails.public_path)

    include ActiveSupport::Callbacks
    define_callbacks :prepare_dispatch, :before_dispatch, :after_dispatch

    def initialize(output = $stdout, request = nil, response = nil)
      @output, @request, @response = output, request, response
    end

    def dispatch_unlocked
      begin
        run_callbacks :before_dispatch
        handle_request
      rescue Exception => exception
        failsafe_rescue exception
      ensure
        run_callbacks :after_dispatch, :enumerator => :reverse_each
      end
    end

    def dispatch
      if ActionController::Base.allow_concurrency
        dispatch_unlocked
      else
        @@guard.synchronize do
          dispatch_unlocked
        end
      end
    end

    def dispatch_cgi(cgi, session_options)
      if cgi ||= self.class.failsafe_response(@output, '400 Bad Request') { CGI.new }
        @request = CgiRequest.new(cgi, session_options)
        @response = CgiResponse.new(cgi)
        dispatch
      end
    rescue Exception => exception
      failsafe_rescue exception
    end

    def call(env)
      @request = RackRequest.new(env)
      @response = RackResponse.new(@request)
      dispatch
    end

    def reload_application
      # Run prepare callbacks before every request in development mode
      run_callbacks :prepare_dispatch

      Routing::Routes.reload
      ActionController::Base.view_paths.reload!
    end

    # Cleanup the application by clearing out loaded classes so they can
    # be reloaded on the next request without restarting the server.
    def cleanup_application
      ActiveRecord::Base.reset_subclasses if defined?(ActiveRecord)
      ActiveSupport::Dependencies.clear
      ActiveRecord::Base.clear_reloadable_connections! if defined?(ActiveRecord)
    end

    def flush_logger
      Base.logger.flush
    end

    def mark_as_test_request!
      @test_request = true
      self
    end

    def test_request?
      @test_request
    end

    def checkin_connections
      # Don't return connection (and peform implicit rollback) if this request is a part of integration test
      return if test_request?
      ActiveRecord::Base.clear_active_connections!
    end

    protected
      def handle_request
        @controller = Routing::Routes.recognize(@request)
        @controller.process(@request, @response).out(@output)
      end

      INTERNAL_SERVER_ERROR = '500 Internal Server Error'.freeze
      BAD_REQUEST           = '400 Bad Request'.freeze

      def failsafe_rescue(exception)
        self.class.failsafe_response(@output, INTERNAL_SERVER_ERROR, exception, @request, @response) do
          if @controller ||= defined?(::ApplicationController) ? ::ApplicationController : Base
            @controller.process_with_exception(@request, @response, exception).out(@output)
          else
            raise exception
          end
        end
      end
  end
end
