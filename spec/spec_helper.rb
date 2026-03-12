# frozen_string_literal: true

require "active_record"
require "strict_associations"

ActiveRecord::Base.establish_connection(
  adapter: "sqlite3",
  database: ":memory:"
)

# Register custom association options (normally done by Railtie)
%i[BelongsTo HasMany HasOne].each do |builder_name|
  ActiveRecord::Associations::Builder
    .const_get(builder_name)
    .singleton_class.prepend(
      Module.new do
        define_method(:valid_options) do |options|
          extra = [:strict]
          extra << :valid_types if builder_name == :BelongsTo
          super(options) + extra
        end
      end
    )
end

# Provide skip_strict_association (normally done by Railtie)
ActiveRecord::Base.class_eval do
  def self.skip_strict_association(*names)
    @_strict_associations_skipped ||= Set.new
    names.each do |n|
      @_strict_associations_skipped.add(n.to_sym)
    end
  end

  def self.strict_associations_skipped
    @_strict_associations_skipped || Set.new
  end

  def self.strict_association_skipped?(name)
    klass = self
    while klass && klass != ActiveRecord::Base
      if klass.strict_associations_skipped.include?(name.to_sym)
        return true
      end

      klass = klass.superclass
    end
    false
  end
end

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end
end
