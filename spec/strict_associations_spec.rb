# frozen_string_literal: true

require "spec_helper"

RSpec.describe StrictAssociations do
  # The validator only inspects association metadata via reflect_on_all_associations;
  # it never queries rows. However, Validator#models_to_check has two guard methods
  # that would reject table-less models:
  #
  #   - safe_table_exists?(model) calls Model.table_exists?
  #   - view?(model) calls connection.view_exists?(table_name)
  #
  # We stub both so our mock models pass through to the actual validation rules
  # without requiring real schema.
  let(:connection) { ActiveRecord::Base.connection }

  before do
    allow(ActiveRecord::Base).to receive(:table_exists?).and_return(true)
    allow(connection).to receive(:view_exists?).and_return(false)
    allow(Object).to receive(:const_source_location).and_return(nil)
  end

  def build_config
    StrictAssociations::Configuration.new
  end

  def validate(models)
    config = build_config
    yield config if block_given?
    StrictAssociations::Validator.new(config, models:).call
  end

  # -- Rule 1: Missing inverse ---

  describe "missing_inverse rule" do
    it "passes when inverse exists" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy
      })
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      violations = validate([author, book])
      inverse_violations = violations.select { |v| v.rule == :missing_inverse }
      expect(inverse_violations).to be_empty
    end

    it "fails when inverse is missing" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
      })
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      violations = validate([book])
      inverse = violations.find { |v| v.rule == :missing_inverse }
      expect(inverse).not_to be_nil
      expect(inverse.model).to eq(book)
      expect(inverse.association_name).to eq(:sa_author)
    end

    it "handles class_name override" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, class_name: "SaBook", dependent: :destroy
      })
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :writer, class_name: "SaAuthor", foreign_key: :sa_author_id
      })

      violations = validate([author, book])
      inverse_violations = violations.select { |v| v.rule == :missing_inverse }
      expect(inverse_violations).to be_empty
    end

    it "handles self-referential associations" do
      node = stub_const("SaNode", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_nodes"
        belongs_to :parent, class_name: "SaNode", optional: true
        has_many :children,
          class_name: "SaNode",
          foreign_key: :parent_id,
          dependent: :destroy
      })

      violations = validate([node])
      inverse_violations = violations.select { |v| v.rule == :missing_inverse }
      expect(inverse_violations).to be_empty
    end

    it "skips polymorphic belongs_to" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true
      })

      violations = validate([comment])
      inverse_violations = violations.select { |v| v.rule == :missing_inverse }
      expect(inverse_violations).to be_empty
    end
  end

  # -- Rule 1b: Missing belongs_to ---

  describe "missing_belongs_to rule" do
    it "passes when belongs_to exists" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      violations = validate([author])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "fails when belongs_to is missing" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
      })

      violations = validate([author])
      bt = violations.find { |v| v.rule == :missing_belongs_to }
      expect(bt).not_to be_nil
      expect(bt.model).to eq(author)
      expect(bt.association_name).to eq(:sa_books)
    end

    it "passes for has_many :through" do
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        has_many :sa_taggings, dependent: :destroy
        has_many :sa_tags, through: :sa_taggings
      })
      stub_const("SaTagging", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_taggings"
        belongs_to :sa_book
        belongs_to :sa_tag
      })
      stub_const("SaTag", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_tags"
      })

      violations = validate([book])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "passes for polymorphic has_many (as:)" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_comments, as: :commentable, dependent: :destroy
      })

      violations = validate([author])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "checks has_one too" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_one :sa_book, dependent: :destroy
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
      })

      violations = validate([author])
      bt = violations.find { |v| v.rule == :missing_belongs_to }
      expect(bt).not_to be_nil
      expect(bt.association_name).to eq(:sa_book)
    end

    it "skips with strict: false" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy, strict: false
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
      })

      violations = validate([SaAuthor])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "handles class_name override" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :novels,
          class_name: "SaBook",
          foreign_key: :sa_author_id,
          dependent: :destroy
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      violations = validate([author])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "passes for STI child when target belongs_to points to parent" do
      parent = stub_const("SaCohort", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_cohorts"
        has_many :sa_enrollments, dependent: :destroy
      })
      child = stub_const("SaCurriculumTemplate", Class.new(parent))
      stub_const("SaEnrollment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_enrollments"
        belongs_to :sa_cohort
      })

      violations = validate([child])
      bt_violations = violations.select { |v| v.rule == :missing_belongs_to }
      expect(bt_violations).to be_empty
    end

    it "fails for non-STI child with different table" do
      parent = stub_const("SaUser", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_users"
        has_many :sa_posts, dependent: :destroy
      })
      child = stub_const("SaSpecialUser", Class.new(parent) {
        self.table_name = "sa_special_users"
      })
      stub_const("SaPost", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_posts"
        belongs_to :sa_user
      })

      violations = validate([child])
      bt = violations.find { |v| v.rule == :missing_belongs_to }
      expect(bt).not_to be_nil
    end
  end

  # -- Rule 2: Polymorphic inverse ---

  describe "polymorphic inverse rules" do
    it "fails when polymorphic has no registered types" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true
      })

      violations = validate([comment])
      v = violations.find { |v| v.rule == :unregistered_polymorphic }
      expect(v).not_to be_nil
      expect(v.model).to eq(comment)
      expect(v.association_name).to eq(:commentable)
    end

    it "passes with inline valid_types" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true, valid_types: %w[SaAuthor]
      })
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_comments, as: :commentable, dependent: :destroy
      })

      violations = validate([comment])
      poly_violations = violations.select do |v|
        v.rule == :unregistered_polymorphic ||
          v.rule == :missing_polymorphic_inverse
      end
      expect(poly_violations).to be_empty
    end

    it "passes when valid_types all define inverse" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true, valid_types: %w[SaAuthor]
      })
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_comments, as: :commentable, dependent: :destroy
      })

      violations = validate([comment])
      poly_violations = violations.select do |v|
        v.rule == :unregistered_polymorphic ||
          v.rule == :missing_polymorphic_inverse
      end
      expect(poly_violations).to be_empty
    end

    it "reports typos in valid_types" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true,
          valid_types: %w[SaAuthor SaBookTypo]
      })
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_comments, as: :commentable, dependent: :destroy
      })

      violations = validate([comment])
      typo_v = violations.find { |v| v.rule == :invalid_valid_type }
      expect(typo_v).not_to be_nil
      expect(typo_v.message).to include("SaBookTypo")
      expect(typo_v.message).to include("Check for typos")
    end

    it "fails when a valid_type lacks the inverse" do
      comment = stub_const("SaComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_comments"
        belongs_to :commentable, polymorphic: true, valid_types: %w[SaAuthor]
      })
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
      })

      violations = validate([comment])
      v = violations.find { |v| v.rule == :missing_polymorphic_inverse }
      expect(v).not_to be_nil
      expect(v.model).to eq(comment)
      expect(v.association_name).to eq(:commentable)
      expect(v.message).to include("SaAuthor")
    end
  end

  # -- Rule 3: Missing dependent ---

  describe "missing_dependent rule" do
    it "passes when dependent is specified" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy
      })

      violations = validate([SaAuthor])
      dep_violations = violations.select do |v|
        v.rule == :missing_dependent
      end
      expect(dep_violations).to be_empty
    end

    it "fails when dependent is missing" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books
      })

      violations = validate([author])
      dep = violations.find do |v|
        v.rule == :missing_dependent
      end
      expect(dep).not_to be_nil
      expect(dep.model).to eq(author)
      expect(dep.association_name).to eq(:sa_books)
    end

    it "skips :through associations" do
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        has_many :sa_taggings, dependent: :destroy
        has_many :sa_tags, through: :sa_taggings
      })
      stub_const("SaTagging", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_taggings"
        belongs_to :sa_book
        belongs_to :sa_tag
      })
      stub_const("SaTag", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_tags"
      })

      violations = validate([book])
      dep_violations = violations.select do |v|
        v.rule == :missing_dependent
      end
      expect(dep_violations).to be_empty
    end

    it "skips associations targeting a view" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
      })

      conn = author.connection
      allow(conn).to receive(:view_exists?).with("sa_books").and_return(true)

      violations = validate([author])
      dep_violations = violations.select do |v|
        v.rule == :missing_dependent
      end
      expect(dep_violations).to be_empty
    end

    it "checks has_one associations too" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_one :sa_book
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
      })

      violations = validate([author])
      dep = violations.find do |v|
        v.rule == :missing_dependent &&
          v.association_name == :sa_book
      end
      expect(dep).not_to be_nil
    end
  end

  # -- Rule 4: HABTM banned ---

  describe "habtm_banned rule" do
    it "flags has_and_belongs_to_many" do
      stub_const("SaTag", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_tags"
      })
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "sa_books"
      end
      book = stub_const("SaBook", klass)
      book.has_and_belongs_to_many(:sa_tags, join_table: :sa_books_sa_tags)

      violations = validate([book])
      habtm = violations.find { |v| v.rule == :habtm_banned }
      expect(habtm).not_to be_nil
      expect(habtm.message).to include("has_many :through")
    end

    it "suppresses HABTM when allow_habtm is set" do
      stub_const("SaTag", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_tags"
      })
      klass = Class.new(ActiveRecord::Base) do
        self.table_name = "sa_books"
      end
      book = stub_const("SaBook", klass)
      book.has_and_belongs_to_many(:sa_tags, join_table: :sa_books_sa_tags)

      violations = validate([book]) { |c| c.allow_habtm }
      habtm = violations.select { |v| v.rule == :habtm_banned }
      expect(habtm).to be_empty
    end
  end

  # -- Rule 5: Orphaned foreign key ---

  describe "orphaned_foreign_key rule" do
    before(:all) do
      ActiveRecord::Base.connection.create_table(:sa_orphan_posts, force: true)

      ActiveRecord::Base.connection.create_table(:sa_orphan_comments, force: true) do |t|
        t.integer :sa_orphan_post_id
        t.integer :author_id
        t.string :commentable_type
        t.integer :commentable_id
        t.integer :score
      end

      ActiveRecord::Base.connection.add_index(:sa_orphan_comments, :sa_orphan_post_id)
      ActiveRecord::Base.connection.add_index(:sa_orphan_comments, :author_id)
      ActiveRecord::Base.connection.add_index(:sa_orphan_comments, :score)
      ActiveRecord::Base.connection.add_index(
        :sa_orphan_comments,
        [:commentable_type, :commentable_id]
      )
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:sa_orphan_comments)
      ActiveRecord::Base.connection.drop_table(:sa_orphan_posts)
    end

    it "fails when indexed FK column exists but no belongs_to is defined" do
      comment = stub_const("SaOrphanComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_comments"
      })

      violations = validate([comment])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      expect(orphan.map(&:association_name)).to contain_exactly(
        :sa_orphan_post, :author
      )
    end

    it "passes when indexed FK column has a matching belongs_to" do
      stub_const("SaOrphanPost", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_posts"
        has_many :sa_orphan_comments, dependent: :destroy
      })
      comment = stub_const("SaOrphanComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_comments"
        belongs_to :sa_orphan_post
        belongs_to :author, class_name: "SaOrphanPost", strict: false
      })

      violations = validate([comment])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      expect(orphan).to be_empty
    end

    it "ignores composite indexes (polymorphic)" do
      comment = stub_const("SaOrphanComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_comments"
        belongs_to :sa_orphan_post
        belongs_to :author, class_name: "SaOrphanPost", strict: false
      })
      stub_const("SaOrphanPost", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_posts"
        has_many :sa_orphan_comments, dependent: :destroy
      })

      violations = validate([comment])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      names = orphan.map(&:association_name)
      expect(names).not_to include(:commentable)
    end

    it "ignores non-_id indexed columns" do
      comment = stub_const("SaOrphanComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_comments"
        belongs_to :sa_orphan_post
        belongs_to :author, class_name: "SaOrphanPost", strict: false
      })
      stub_const("SaOrphanPost", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_posts"
        has_many :sa_orphan_comments, dependent: :destroy
      })

      violations = validate([comment])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      names = orphan.map(&:association_name)
      expect(names).not_to include(:score)
    end

    it "skips with skip_strict_association" do
      comment = stub_const("SaOrphanComment", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orphan_comments"
        skip_strict_association :sa_orphan_post
        skip_strict_association :author
      })

      violations = validate([comment])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      expect(orphan).to be_empty
    end
  end

  # -- Inline skip mechanisms ---

  describe "strict: false option" do
    it "skips has_many with strict: false" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, strict: false
      })

      violations = validate([SaAuthor])
      dep_violations = violations.select { |v| v.association_name == :sa_books }
      expect(dep_violations).to be_empty
    end

    it "skips belongs_to with strict: false" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
      })
      book = stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author, strict: false
      })

      violations = validate([book])
      inverse_violations = violations.select { |v| v.rule == :missing_inverse }
      expect(inverse_violations).to be_empty
    end

    it "skips has_one with strict: false" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_one :sa_book, strict: false
      })

      violations = validate([SaAuthor])
      dep_violations = violations.select { |v| v.association_name == :sa_book }
      expect(dep_violations).to be_empty
    end
  end

  describe "skip_strict_association" do
    it "skips a named association" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        skip_strict_association :sa_books
        has_many :sa_books
      })

      violations = validate([author])
      dep_violations = violations.select { |v| v.association_name == :sa_books }
      expect(dep_violations).to be_empty
    end

    it "inherits skips from superclass (STI)" do
      parent = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        skip_strict_association :sa_books
        has_many :sa_books
      })
      stub_const("SaSpecialAuthor", Class.new(parent))

      violations = validate([SaSpecialAuthor])
      dep_violations = violations.select { |v| v.association_name == :sa_books }
      expect(dep_violations).to be_empty
    end
  end

  # -- Third-party model skipping ---

  describe "third-party model skipping" do
    def with_source_location(model, path)
      allow(Object).to receive(:const_source_location)
        .with(model.name).and_return([path, 1])
    end

    it "skips models defined outside the app root" do
      gem_path = File.expand_path(Dir.pwd) + "/../some_gem/lib/model.rb"
      author = stub_const("SaGemAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books
      })
      with_source_location(author, gem_path)

      violations = validate([author])
      expect(violations).to be_empty
    end

    it "checks models defined inside the app root" do
      app_path = File.expand_path(Dir.pwd) + "/app/models/author.rb"
      author = stub_const("SaAppAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books
      })
      with_source_location(author, app_path)

      violations = validate([author])
      expect(violations).not_to be_empty
    end

    it "skips inherited associations from third-party parent" do
      gem_path = File.expand_path(Dir.pwd) + "/../doorkeeper/lib/model.rb"
      app_path = File.expand_path(Dir.pwd) + "/app/models/my_token.rb"

      parent = stub_const("SaGemToken", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_gem_tokens"
        has_many :sa_things, dependent: :destroy
      })
      with_source_location(parent, gem_path)

      stub_const("SaThing", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_things"
        belongs_to :sa_gem_token
      })

      child = stub_const("SaAppToken", Class.new(parent) {
        has_many :sa_extras, dependent: :destroy, strict: false
      })
      with_source_location(child, app_path)

      violations = validate([child])
      inherited = violations.select { |v| v.association_name == :sa_things }
      expect(inherited).to be_empty
    end

    it "checks associations defined directly on app STI subclass" do
      gem_path = File.expand_path(Dir.pwd) + "/../doorkeeper/lib/model.rb"
      app_path = File.expand_path(Dir.pwd) + "/app/models/my_token.rb"

      parent = stub_const("SaGemToken2", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_gem_tokens"
      })
      with_source_location(parent, gem_path)

      child = stub_const("SaAppToken2", Class.new(parent) {
        has_many :sa_widgets, dependent: :destroy
      })
      with_source_location(child, app_path)

      stub_const("SaWidget", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_widgets"
      })

      violations = validate([child])
      widget_v = violations.find do |v|
        v.association_name == :sa_widgets &&
          v.rule == :missing_belongs_to
      end
      expect(widget_v).not_to be_nil
    end
  end

  describe "owns_table? for orphaned FK checks" do
    before(:all) do
      ActiveRecord::Base.connection.create_table(
        :sa_sti_parents, force: true
      ) do |t|
        t.string :type
        t.integer :org_id
      end

      ActiveRecord::Base.connection.add_index(:sa_sti_parents, :org_id)
    end

    after(:all) do
      ActiveRecord::Base.connection.drop_table(:sa_sti_parents)
    end

    it "checks orphaned FKs on the table-owning parent" do
      parent = stub_const("SaStiParent", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_sti_parents"
      })

      violations = validate([parent])
      orphan = violations.find do |v|
        v.rule == :orphaned_foreign_key &&
          v.association_name == :org
      end
      expect(orphan).not_to be_nil
    end

    it "skips orphaned FK checks on STI children" do
      parent = stub_const("SaStiParent", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_sti_parents"
      })
      child = stub_const("SaStiChild", Class.new(parent))

      violations = validate([child])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      expect(orphan).to be_empty
    end

    it "passes when STI child defines the belongs_to" do
      stub_const("SaOrg", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_orgs"
      })
      parent = stub_const("SaStiParent", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_sti_parents"
      })
      stub_const("SaStiChild", Class.new(parent) {
        belongs_to :org, class_name: "SaOrg", strict: false
      })

      violations = validate([parent])
      orphan = violations.select { |v| v.rule == :orphaned_foreign_key }
      expect(orphan).to be_empty
    end
  end

  # -- Configuration ---

  describe "configuration" do
    it "skips models backed by database views" do
      author = stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        belongs_to :sa_author
        has_many :sa_books
      })

      conn = author.connection
      allow(conn).to receive(:view_exists?).with("sa_authors").and_return(true)

      violations = validate([author])
      expect(violations).to be_empty
    end

    it "skips models backed by PostgreSQL materialized views" do
      mview = stub_const("SaMview", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_mview"
        belongs_to :sa_author
        has_many :sa_books
      })

      conn = mview.connection
      allow(conn).to receive(:adapter_name).and_return("PostgreSQL")
      allow(conn).to receive(:select_value)
        .with("SELECT 1 FROM pg_matviews WHERE matviewname = 'sa_mview'")
        .and_return(1)

      violations = validate([mview])
      expect(violations).to be_empty
    end
  end

  # -- Public API ---

  describe ".validate!" do
    it "raises ViolationError with formatted message" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      expect { StrictAssociations.validate!(models: [SaBook]) }
        .to raise_error(StrictAssociations::ViolationError, /missing_inverse/)
    end

    it "does not raise when all associations are valid" do
      stub_const("SaAuthor", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_authors"
        has_many :sa_books, dependent: :destroy
      })
      stub_const("SaBook", Class.new(ActiveRecord::Base) {
        self.table_name = "sa_books"
        belongs_to :sa_author
      })

      expect { StrictAssociations.validate!(models: [SaAuthor, SaBook]) }
        .not_to raise_error
    end
  end
end
