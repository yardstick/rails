module Rails

  module RailsLts

    class << self

      attr_accessor :configuration

      def finalize
        finalize_param_parsers
      end


      private

      def finalize_param_parsers
        unless configuration.enable_json_parsing
          ActionController::Base.param_parsers.delete(Mime::JSON)
        end
        unless configuration.enable_xml_parsing
          ActionController::Base.param_parsers.delete(Mime::XML)
        end
      end

    end


    class Configuration

      attr_accessor :enable_json_parsing
      attr_accessor :enable_xml_parsing

      def initialize(options)
        unless Rails.configuration.rails_lts_options
          $stderr.puts(%{Please configure your rails_lts_options using config.rails_lts_options inside Rails::Initializer.run. Defaulting to "rails_lts_options = { :default => :compatible }"})
        end

        options ||= {}

        set_defaults(options.delete(:default) || :compatible)

        options.each do |key, value|
          self.send("#{key}=", value)
        end
      end

      def set_defaults(default)
        unless [:hardened, :compatible].include?(default)
          raise ArgumentError.new("Rails LTS: default needs to be :hardened or :compatible")
        end
        case default
        when :hardened
          self.enable_json_parsing = false
          self.enable_xml_parsing = false
        when :compatible
          self.enable_json_parsing = true
          self.enable_xml_parsing = true
        end
      end

    end

  end

end
