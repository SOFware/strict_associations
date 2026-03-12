# Changelog

## [0.1.0] - 2026-03-12

### Added

- Initial release
- Validates `has_many` and `has_one` associations declare `:dependent`
- Validates `belongs_to` associations have a matching inverse
- Validates polymorphic `belongs_to` declares `valid_types:`
- Detects `has_and_belongs_to_many` usage (configurable)
- Per-association opt-out via `strict: false`
- Per-model opt-out via `skip_strict_association`
- Railtie for automatic setup in Rails applications
