# frozen_string_literal: true

require_relative "lib/strict_associations/version"

Gem::Specification.new do |spec|
  spec.name = "strict_associations"
  spec.version = StrictAssociations::VERSION
  spec.authors = ["Jeff Lange"]
  spec.email = ["jeff.lange@sofwarellc.com"]

  spec.summary = <<~MSG
    Enforces explicit definition of both sides of ActiveRecord associations
    (e.g. belongs_to, has_many)
  MSG
  spec.description = <<~MSG
    Enforces that both sides of an association (e.g. belongs_to, has_many) are
    explicitly defined. Enforces that has_many (or has_one) associations define a
    :dependent option, or explicitly opt-out via `strict: false`
  MSG
  spec.homepage = "https://github.com/SOFware/strict_associations"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"

  spec.files = Dir.chdir(__dir__) do
    Dir["{lib}/**/*", "LICENSE.txt", "CHANGELOG.md"]
  end
  spec.require_paths = ["lib"]

  spec.add_dependency "activerecord", ">= 7.0", "< 9"
  spec.add_dependency "railties", ">= 7.0", "< 9"

  spec.add_development_dependency "rspec", "~> 3.0"
  spec.add_development_dependency "sqlite3", "~> 2.0"
  spec.add_development_dependency "standard", "~> 1.0"
  spec.add_development_dependency "simplecov", "~> 0.22"
  spec.add_development_dependency "reissue", "~> 0.4"
end
