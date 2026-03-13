# frozen_string_literal: true

module StrictAssociations
  class Validator
    def initialize(configuration, models: nil)
      @config = configuration
      @explicit_models = models
    end

    def call
      violations = []

      models_to_check.each do |model|
        check_habtm(model, violations)
        check_belongs_to_inverses(model, violations)
        check_has_many_inverses(model, violations)
        check_polymorphic_inverses(model, violations)
        check_dependent_options(model, violations)
        check_orphaned_foreign_keys(model, violations)
      end

      violations
    end

    private

    attr_reader :config, :explicit_models

    def models_to_check
      candidates = explicit_models || all_models
      candidates.reject do |model|
        model.abstract_class? ||
          !safe_table_exists?(model) ||
          view?(model) ||
          third_party?(model)
      end
    end

    def all_models
      ActiveRecord::Base.descendants.reject(&:abstract_class?)
    end

    def safe_table_exists?(model)
      model.table_exists?
    rescue ActiveRecord::NoDatabaseError
      false
    end

    def view?(model)
      conn = model.connection
      table = model.table_name
      conn.view_exists?(table) || materialized_view?(conn, table)
    rescue ActiveRecord::NoDatabaseError
      false
    end

    def materialized_view?(conn, table_name)
      return false unless conn.adapter_name == "PostgreSQL"

      conn.select_value(
        "SELECT 1 FROM pg_matviews WHERE matviewname = " \
        "#{conn.quote(table_name)}"
      ).present?
    end

    def check_habtm(model, violations)
      return if config.habtm_allowed?

      habtm = :has_and_belongs_to_many
      model.reflect_on_all_associations(habtm).each do |ref|
        next if skipped?(model, ref)

        violations << Violation.new(
          model:,
          association_name: ref.name,
          rule: :habtm_banned,
          message: <<~MSG.squish
            has_and_belongs_to_many is not allowed.
            Use a join model with has_many :through instead.
          MSG
        )
      end
    end

    def check_belongs_to_inverses(model, violations)
      refs = model.reflect_on_all_associations(:belongs_to)
      refs.each do |ref|
        next if skipped?(model, ref)
        next if ref.options[:polymorphic]

        target = resolve_target(ref)
        next unless target

        unless inverse_exists?(model, ref, target)
          fk = ref.foreign_key
          inverse_name = model.table_name.to_sym
          violations << Violation.new(
            model:,
            association_name: ref.name,
            rule: :missing_inverse,
            message: <<~MSG.squish
              #{target} has no has_many/has_one pointing back to \
              #{model.table_name} with foreign key #{fk}.
              Define the inverse.
              Or mark this association with strict: false.
              Or call skip_strict_association :#{inverse_name}
              on #{target}
            MSG
          )
        end
      end
    end

    def check_has_many_inverses(model, violations)
      %i[has_many has_one].each do |macro|
        model.reflect_on_all_associations(macro).each do |ref|
          next if skipped?(model, ref)
          next if ref.is_a?(ActiveRecord::Reflection::ThroughReflection)
          next if ref.options[:as] # skip for polymorphic inverse

          target = resolve_target(ref)
          next unless target

          unless belongs_to_exists?(model, ref, target)
            violations << Violation.new(
              model:,
              association_name: ref.name,
              rule: :missing_belongs_to,
              message: <<~MSG.squish
                #{model} has #{macro} :#{ref.name} but #{target} has no belongs_to \
                pointing back with foreign key #{ref.foreign_key}.
                Define the belongs_to on #{target}.
                Or mark with strict: false.
                Or call skip_strict_association :#{ref.name} on #{model}.
              MSG
            )
          end
        end
      end
    end

    def check_polymorphic_inverses(model, violations)
      refs = model.reflect_on_all_associations(:belongs_to)
      refs.each do |ref|
        next if skipped?(model, ref)
        next unless ref.options[:polymorphic]

        resolved = resolve_valid_types(model, ref)

        unless resolved
          violations << Violation.new(
            model:,
            association_name: ref.name,
            rule: :unregistered_polymorphic,
            message: <<~MSG.squish
              #{model}##{ref.name} is polymorphic but has no valid_types declared.
              Add valid_types: to the association. Or mark with strict: false.
            MSG
          )
          next
        end

        type_violations, types = resolved.partition { |r| r.is_a?(Violation) }
        violations.concat(type_violations)
        check_registered_polymorphic_types(model, ref, types, violations)
      end
    end

    def resolve_valid_types(model, ref)
      inline = ref.options[:valid_types]
      return unless inline

      resolved = []
      Array(inline).each do |t|
        resolved << t.to_s.constantize
      rescue NameError => e
        resolved << Violation.new(
          model:,
          association_name: ref.name,
          rule: :invalid_valid_type,
          message: <<~MSG.squish
            #{model}##{ref.name} declares valid_types containing "#{t}" but \
            #{e.message}. Check for typos in valid_types.
          MSG
        )
      end

      resolved
    end

    def check_registered_polymorphic_types(model, ref, types, violations)
      fk = ref.foreign_key.to_s
      source_table = model.table_name

      types.each do |type_class|
        next if polymorphic_inverse_exists?(type_class, source_table, fk)

        violations << Violation.new(
          model:,
          association_name: ref.name,
          rule: :missing_polymorphic_inverse,
          message: <<~MSG.squish
            #{type_class} is registered for #{model}##{ref.name} but has no \
            has_many/has_one pointing back to #{source_table} with foreign key #{fk}.
          MSG
        )
      end
    end

    def check_dependent_options(model, violations)
      %i[has_many has_one].each do |macro|
        model.reflect_on_all_associations(macro).each do |ref|
          next if skipped?(model, ref)
          next if ref.is_a?(ActiveRecord::Reflection::ThroughReflection)
          next if target_is_view?(ref)

          unless ref.options.key?(:dependent)
            violations << Violation.new(
              model:,
              association_name: ref.name,
              rule: :missing_dependent,
              message: <<~MSG.squish
                #{model}##{ref.name} is missing a :dependent option.
                Add dependent: :destroy, :delete_all, :nullify, or \
                :restrict_with_exception.
                Or mark with strict: false.
                Or call skip_strict_association :#{ref.name} on #{model}.
              MSG
            )
          end
        end
      end
    end

    def check_orphaned_foreign_keys(model, violations)
      return unless owns_table?(model)

      indexed_fk_columns = indexed_foreign_key_columns(model)
      defined_fk_columns = sti_family_foreign_keys(model)

      (indexed_fk_columns - defined_fk_columns).each do |column|
        assoc_name = column.delete_suffix("_id").to_sym
        next if model.strict_association_skipped?(assoc_name)

        violations << Violation.new(
          model:,
          association_name: assoc_name,
          rule: :orphaned_foreign_key,
          message: <<~MSG.squish
            #{model.table_name} has an indexed column #{column} but #{model} has no \
            belongs_to association for it.
            Define a belongs_to.
            Or remove the index.
            Or call skip_strict_association :#{assoc_name} on #{model}.
          MSG
        )
      end
    end

    # Collects belongs_to foreign keys from the model and all STI descendants sharing
    # the same table. We check this because a belongs_to may be defined on one of the
    # STI subclasses rather than the parent. In that case, a belongs_to IS defined,
    # so we shouldn't raise a violation.
    def sti_family_foreign_keys(model)
      model_family = [model] + model.descendants.select do |descendant|
        descendant.table_name == model.table_name
      end

      model_family.flat_map do |family_model|
        family_model
          .reflect_on_all_associations(:belongs_to)
          .map { |ref| ref.foreign_key.to_s }
      end.uniq
    end

    def indexed_foreign_key_columns(model)
      model.connection.indexes(model.table_name).filter_map do |index|
        columns = index.columns
        next unless columns.is_a?(Array) && columns.one?
        next unless columns.first.end_with?("_id")

        columns.first
      end
    end

    def resolve_target(reflection)
      reflection.klass
    rescue NameError
      nil
    end

    def belongs_to_exists?(source_model, has_many_ref, target)
      fk = has_many_ref.foreign_key.to_s

      target.reflect_on_all_associations(:belongs_to).any? do |ref|
        next if ref.options[:polymorphic]

        begin
          # The table_name guard ensures this only applies for true STI (shared
          # table), not unrelated inheritance with different tables.
          source_model.table_name == ref.klass.table_name &&
            ref.foreign_key.to_s == fk
        rescue NameError
          false
        end
      end
    end

    def inverse_exists?(source_model, belongs_to_ref, target)
      fk = belongs_to_ref.foreign_key.to_s
      source_table = source_model.table_name

      target.reflect_on_all_associations.any? do |ref|
        next unless %i[has_many has_one].include?(ref.macro)
        next if ref.is_a?(ActiveRecord::Reflection::ThroughReflection)

        begin
          ref.klass.table_name == source_table && ref.foreign_key.to_s == fk
        rescue NameError
          false
        end
      end
    end

    def polymorphic_inverse_exists?(type, table, fk)
      type.reflect_on_all_associations.any? do |ref|
        next unless %i[has_many has_one].include?(ref.macro)
        next if ref.is_a?(ActiveRecord::Reflection::ThroughReflection)

        begin
          ref.klass.table_name == table && ref.foreign_key.to_s == fk
        rescue NameError
          false
        end
      end
    end

    def target_is_view?(reflection)
      target = resolve_target(reflection)
      target && view?(target)
    end

    def skipped?(model, ref)
      ref.options[:strict] == false ||
        model.strict_association_skipped?(ref.name) || third_party?(ref.active_record)
    end

    def third_party?(model)
      return false unless model.name

      source = Object.const_source_location(model.name)&.first
      return false unless source

      !File.expand_path(source).start_with?(app_root)
    end

    def app_root
      @app_root ||= File.expand_path(defined?(Rails) ? Rails.root.to_s : Dir.pwd)
    end

    def owns_table?(model)
      model.superclass == ActiveRecord::Base ||
        model.table_name != model.superclass.table_name
    end
  end
end
