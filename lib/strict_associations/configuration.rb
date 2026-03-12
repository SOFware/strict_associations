# frozen_string_literal: true

module StrictAssociations
  class Configuration
    def initialize
      @habtm_allowed = false
    end

    def allow_habtm(value = true)
      @habtm_allowed = value
    end

    def habtm_allowed?
      @habtm_allowed
    end
  end
end
