# StrictAssociations

## What it does

#### Summary
Enforces explicit definitions of both sides of ActiveRecord associations
(e.g. belongs_to, has_many)

#### StrictAssociations enforces 5 rules:
1. `:missing_inverse` - Every `belongs_to` must have a corresponding `has_many` or
   `has_one` on the target model pointing back
2. `:missing_dependent` - Every direct `has_many` or `has_one` must declare a
   `:dependent` option (`:destroy`, `:nullify`, etc)
3. `:unregistered_polymorphic` - Every polymorphic `belongs_to` must declare
   `:valid_types`
4. `:missing_polymorphic_inverse` - Each registered polymorphic type must have a
   `has_many` or `has_one` pointing back
5. `:habtm_banned` - No `has_and_belongs_to_many` allowed

## How to use

### Normal case: StrictAssociation enforces doing it right
```ruby
class Foo < ApplicationRecord
end

class Bar < ApplicationRecord
  belongs_to :foo
end

# => StrictAssociation::ViolationError
#
# We failed to define the has_many association
```
```ruby
class Foo < ApplicationRecord
  has_many :bars
end

class Bar < ApplicationRecord
  belongs_to :foo
end

# => StrictAssociation::ViolationError
#
# We failed to define the :dependent option for the has_many association
```
```ruby
class Foo < ApplicationRecord
  has_many :bars, dependent: :destroy
end

class Bar < ApplicationRecord
  belongs_to :foo
end

# => Good
```

### Ignore in cases where StrictAssociations don't make sense
```ruby
# "I know this model doesn't have a has_many pointing back; that's intentional"
belongs_to :foo, strict: false

# "I'm handling dependents manually" (e.g. such as in a callback)
has_many :bars, strict: false

# "I'm purposely not defining the association"
skip_strict_association :bars
```

### Sample error message
```
StrictAssociations found 1 violation(s): (StrictAssociations::ViolationError)

Foo.bars [missing_dependent]: Foo#bars is missing a :dependent option.
Add dependent: :destroy, :delete_all, :nullify, or :restrict_with_exception. Or mark
with strict: false. Or call skip_strict_association :bars on Foo.
```
### Polymorphic associations
You must specify `valid_types` for polymorphic models. These are then also checked
along with other strict associations.

#### Example
```ruby
class Role < ActiveRecord::Base
  belongs_to :resource, polymorphic: true
end

class Document < ActiveRecord::Base
  has_many :roles, dependent: :destroy
end

# => StrictAssociation::ViolationError
# We failed to define :valid_types for the polymorphic belongs_to
```
```ruby
class Role < ActiveRecord::Base
  belongs_to :resource, polymorphic: true, valid_types: %i[Document Organization]
end

class Document < ActiveRecord::Base
end

# => StrictAssociation::ViolationError
# We failed to define the has_many
```
```ruby
class Role < ActiveRecord::Base
  belongs_to :resource, polymorphic: true, valid_types: %i[Document Organization]
end

class Document < ActiveRecord::Base
  has_many :roles, dependent: :destroy
end

# => Good
```
