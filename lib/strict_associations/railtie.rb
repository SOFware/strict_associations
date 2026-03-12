# frozen_string_literal: true

module StrictAssociations
  class Railtie < Rails::Railtie
    initializer "strict_associations.extend_active_record" do
      ActiveSupport.on_load(:active_record) do
        # Register :strict and :valid_types as recognized association options
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

        # Provide .skip_strict_association on all models
        #
        # Inside on_load(:active_record), self is ActiveRecord::Base, so we define
        # directly.
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
            return true if klass.strict_associations_skipped.include?(name.to_sym)

            klass = klass.superclass
          end
          false
        end
      end
    end
  end
end
