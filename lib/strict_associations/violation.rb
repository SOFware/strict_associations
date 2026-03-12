# frozen_string_literal: true

module StrictAssociations
  class Violation
    attr_reader :model, :association_name, :rule, :message

    def initialize(model:, association_name:, rule:, message:)
      @model = model
      @association_name = association_name
      @rule = rule
      @message = message
    end
  end
end
