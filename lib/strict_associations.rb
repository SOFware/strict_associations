# frozen_string_literal: true

require_relative "strict_associations/version"
require_relative "strict_associations/configuration"
require_relative "strict_associations/validator"
require_relative "strict_associations/violation"
require_relative "strict_associations/railtie" if defined?(Rails::Railtie)

module StrictAssociations
  class ViolationError < StandardError; end

  class << self
    def configure(&block)
      @configure_block = block
      block.call(configuration)
    end

    def configuration
      @configuration ||= Configuration.new
    end

    def validate!(models: nil)
      eager_load_if_needed
      config = Configuration.new
      @configure_block&.call(config)
      @configuration = config

      validator = Validator.new(config, models:)
      violations = validator.call

      return if violations.empty?

      raise ViolationError, format_violations(violations)
    end

    def reset!
      @configuration = nil
      @configure_block = nil
    end

    private

    def eager_load_if_needed
      return unless defined?(Rails)
      return if Rails.application.config.eager_load

      Rails.application.eager_load!
    end

    def format_violations(violations)
      lines = violations.map do |v|
        "  #{v.model}.#{v.association_name}" \
          " [#{v.rule}]: #{v.message}"
      end

      <<~MSG
        StrictAssociations found #{violations.size} violation(s):

        #{lines.join("\n")}
      MSG
    end
  end
end
