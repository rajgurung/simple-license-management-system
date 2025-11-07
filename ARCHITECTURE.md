# License Management System - Architecture

## Overview

This application uses a layered architecture pattern with clear separation of concerns:
- **Controllers** handle HTTP requests and responses
- **Services** contain business logic and orchestration
- **Queries** encapsulate complex database queries
- **Models** define data structure and relationships

## Data Flow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  HTTP Request: POST /accounts/1/products/2/bulk_assign     │
└────────────────────┬────────────────────────────────────────┘
                     │
                     ▼
┌─────────────────────────────────────────────────────────────┐
│  CONTROLLER: LicenseAssignmentsController                   │
│  File: app/controllers/license_assignments_controller.rb    │
│                                                              │
│  def bulk_assign                                            │
│    1. Extracts params (user_ids, mode)                      │
│    2. Creates SERVICE instance                              │
│    3. Calls service.call                                    │
│    4. Returns response                                      │
└──────────────────────────────────────────┬──────────────────┘
                                           │
                                           ▼
┌─────────────────────────────────────────────────────────────┐
│  SERVICE: Assignments::AssignWithAdvisoryLock               │
│  File: app/services/assignments/assign_with_advisory_lock.rb│
│                                                              │
│  def call                                                   │
│    1. Acquires database lock (concurrency)                  │
│    2. Filters existing holders (uses Query)                 │
│    3. Checks capacity (uses Query)                          │
│    4. Assigns licenses (bulk insert)                        │
│    5. Logs events (structured logging)                      │
│    6. Returns result                                        │
└──────────────────────────────┬───────────┬──────────────────┘
                               │           │
               ┌───────────────┘           └──────────────┐
               │                                          │
               ▼                                          ▼
┌──────────────────────────────┐  ┌──────────────────────────────┐
│  QUERY: ExistingHoldersQuery │  │  QUERY: PoolAvailabilityQuery│
│  app/queries/                │  │  app/queries/                │
│  existing_holders_query.rb   │  │  pool_availability_query.rb  │
│                              │  │                              │
│  user_ids                    │  │  available_licenses          │
│   - Returns IDs of users     │  │   - total_licenses           │
│     with active licenses     │  │   - assigned_licenses        │
│   - Filters by active subs   │  │   - Returns available count  │
└──────────────┬───────────────┘  └──────────────┬───────────────┘
               │                                  │
               └──────────────┬───────────────────┘
                              │
                              ▼
                    ┌──────────────────┐
                    │  DATABASE        │
                    │  Models:         │
                    │  - Subscription  │
                    │  - LicenseAssign │
                    │  - User          │
                    │  - Account       │
                    │  - Product       │
                    └──────────────────┘
```

## Directory Structure

```
app/
├── controllers/
│   ├── application_controller.rb
│   ├── accounts_controller.rb
│   ├── products_controller.rb
│   ├── subscriptions_controller.rb
│   ├── users_controller.rb
│   ├── sessions_controller.rb
│   └── license_assignments_controller.rb    [Main controller for license ops]
│
├── services/
│   ├── assignments/
│   │   ├── assign_with_advisory_lock.rb    [License assignment logic]
│   │   └── no_capacity_error.rb             [Custom error class]
│   └── concurrency/
│       └── advisory_lock_key.rb             [PostgreSQL advisory lock helper]
│
├── queries/
│   ├── existing_holders_query.rb            [Find users with licenses]
│   └── pool_availability_query.rb           [Calculate license capacity]
│
└── models/
    ├── account.rb
    ├── product.rb
    ├── subscription.rb
    ├── user.rb
    └── license_assignment.rb
```

## How Components Connect

### 1. Controller → Query (Direct Access)

Controllers can use Queries directly for read operations:

```ruby
# app/controllers/license_assignments_controller.rb (lines 17-21)

capacity_query = PoolAvailabilityQuery.new(
  account_id: @account.id,
  product_id: @product.id
)
@capacity = capacity_query.capacity_details
# Returns: { total: 10, used: 5, available: 5 }
```

### 2. Controller → Service

Controllers delegate business logic to Services:

```ruby
# app/controllers/license_assignments_controller.rb (lines 41-48)

service = Assignments::AssignWithAdvisoryLock.new(
  account_id: @account.id,
  product_id: @product.id,
  user_ids: user_ids,
  mode: mode
)

result = service.call
# Returns: { assigned: [1,2,3], overflow: [], outcome: 'full' }
```

### 3. Service → Queries (Internal)

Services use Queries to retrieve data needed for business logic:

```ruby
# app/services/assignments/assign_with_advisory_lock.rb

# Filter existing holders (lines 115-122)
def filter_existing_holders
  existing = ExistingHoldersQuery.new(
    account_id: account_id,
    product_id: product_id
  ).user_ids

  user_ids - existing  # Remove already assigned users
end

# Calculate available capacity (lines 123-127)
def calculate_available_capacity
  PoolAvailabilityQuery.new(
    account_id: account_id,
    product_id: product_id
  ).available_licenses
end
```

## Query Objects Pattern

### Purpose

Query Objects encapsulate complex database queries into reusable, testable classes:

**Benefits:**
- Single Responsibility: Each query has one job
- Reusability: Used by multiple controllers/services
- Testability: Easy to test in isolation
- Readability: Clear intent through naming
- Maintainability: Changes centralized in one place

### Example: PoolAvailabilityQuery

```ruby
# app/queries/pool_availability_query.rb

class PoolAvailabilityQuery
  attr_reader :account_id, :product_id

  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  # Main method: returns available license count
  def available_licenses
    total_licenses - assigned_licenses
  end

  # Calculate total licenses from all active subscriptions
  def total_licenses
    Subscription
      .active
      .where(account_id: account_id, product_id: product_id)
      .sum(:number_of_licenses)
  end

  # Count currently assigned licenses (with active subscriptions)
  def assigned_licenses
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON ...")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct  # Prevents double-counting with multiple subscriptions
      .count
  end

  # Returns detailed capacity info
  def capacity_details
    total = total_licenses
    used = assigned_licenses
    {
      total: total,
      used: used,
      available: total - used
    }
  end
end
```

### Example: ExistingHoldersQuery

```ruby
# app/queries/existing_holders_query.rb

class ExistingHoldersQuery
  attr_reader :account_id, :product_id

  def initialize(account_id:, product_id:)
    @account_id = account_id
    @product_id = product_id
  end

  # Returns user IDs who currently have licenses
  def user_ids
    LicenseAssignment
      .where(account_id: account_id, product_id: product_id)
      .joins("INNER JOIN subscriptions ON ...")
      .where('subscriptions.expires_at > ?', Time.current)
      .distinct  # Prevents duplicates with multiple subscriptions
      .pluck(:user_id)
  end

  # Helper method: remove existing holders from array
  def exclude_from(user_ids_array)
    user_ids_array - user_ids
  end
end
```

## Service Objects Pattern

### Purpose

Service Objects encapsulate business logic and orchestrate complex operations:

**Benefits:**
- Business Logic Isolation: Controllers stay thin
- Transaction Management: Ensures data consistency
- Concurrency Control: Advisory locks prevent race conditions
- Logging: Structured event logging for debugging
- Error Handling: Custom error classes with context
- Testability: Business logic tested independently

### Example: AssignWithAdvisoryLock Service

```ruby
# app/services/assignments/assign_with_advisory_lock.rb

module Assignments
  class AssignWithAdvisoryLock
    attr_reader :account_id, :product_id, :user_ids, :mode

    def initialize(account_id:, product_id:, user_ids:, mode: :all_or_nothing)
      @account_id = account_id
      @product_id = product_id
      @user_ids = Array(user_ids).map(&:to_i)  # Normalize to integers
      @mode = mode.to_sym
    end

    def call
      log_event("license_assignment_start", ...)

      ActiveRecord::Base.transaction do
        # Step 1: Acquire PostgreSQL advisory lock
        acquire_advisory_lock

        # Step 2: Filter out users who already have licenses
        eligible_user_ids = filter_existing_holders
        log_event("license_assignment_filter", ...)

        # Step 3: Check available capacity
        available = calculate_available_capacity
        log_event("license_assignment_capacity_check", ...)

        # Step 4: Handle capacity constraints
        case mode
        when :all_or_nothing
          raise NoCapacityError if requested > available
          users_to_assign = eligible_user_ids
        when :partial_fill
          users_to_assign = eligible_user_ids.first(available)
        end

        # Step 5: Bulk insert assignments
        LicenseAssignment.insert_all(assignments_data)

        log_event("license_assignment_success", ...)

        # Return result
        {
          assigned: users_to_assign,
          overflow: eligible_user_ids - users_to_assign,
          outcome: determine_outcome(...)
        }
      end
    end

    private

    # Uses ExistingHoldersQuery
    def filter_existing_holders
      existing = ExistingHoldersQuery.new(...).user_ids
      user_ids - existing
    end

    # Uses PoolAvailabilityQuery
    def calculate_available_capacity
      PoolAvailabilityQuery.new(...).available_licenses
    end

    # Structured JSON logging
    def log_event(event, **data)
      Rails.logger.info({
        ts: Time.current.iso8601,
        level: "info",
        svc: "license_management",
        env: Rails.env,
        event: event,
        **data
      }.to_json)
    end
  end
end
```

## Responsibility Matrix

| Layer | Responsibility | Examples |
|-------|---------------|----------|
| **Controller** | - HTTP request/response<br>- Parameter extraction<br>- Authentication/Authorization<br>- Render views/JSON | `bulk_assign` action<br>`set_account_and_product` |
| **Service** | - Business logic<br>- Transaction management<br>- Orchestration<br>- Logging<br>- Error handling | `AssignWithAdvisoryLock.call`<br>Acquire locks<br>Coordinate operations |
| **Query** | - Database queries<br>- Data retrieval<br>- Calculations<br>- Filtering | `PoolAvailabilityQuery`<br>`ExistingHoldersQuery`<br>Complex JOINs |
| **Model** | - Data structure<br>- Validations<br>- Associations<br>- Scopes | `LicenseAssignment`<br>`Subscription.active`<br>Relationships |

## Key Design Decisions

### 1. Advisory Locks (PostgreSQL)

**Why:** Prevents race conditions when multiple users assign licenses simultaneously.

```ruby
# Generates unique lock ID based on account + product
lock_key = Concurrency::AdvisoryLockKey.for_pool(account_id, product_id)
ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(#{lock_key})")
```

### 2. Type Normalization

**Problem:** Controller params are strings, database IDs are integers.

**Solution:** Normalize in service initialization:

```ruby
@user_ids = Array(user_ids).map(&:to_i)
```

### 3. Distinct Counts

**Problem:** Multiple subscriptions cause double-counting in JOINs.

**Solution:** Use `.distinct` before counting:

```ruby
LicenseAssignment
  .where(...)
  .joins("... subscriptions ...")
  .distinct  # Prevents double-counting
  .count
```

### 4. Structured Logging

**Why:** JSON logs are easily parsed by log aggregators (Railway, Datadog, etc.)

```ruby
Rails.logger.info({
  ts: Time.current.iso8601,
  event: "license_assignment_start",
  account_id: 1,
  product_id: 2,
  requested_user_ids: 5
}.to_json)
```

## Testing Strategy

- **Controllers:** Request specs test HTTP layer
- **Services:** Unit tests for business logic
- **Queries:** Unit tests for data retrieval
- **Models:** Model specs for validations/associations

Example test structure:
```
spec/
├── requests/
│   └── license_assignments_spec.rb      [Controller integration]
├── services/
│   └── assignments/
│       └── assign_with_advisory_lock_spec.rb  [Service unit tests]
└── queries/
    ├── pool_availability_query_spec.rb  [Query unit tests]
    └── existing_holders_query_spec.rb   [Query unit tests]
```

## Common Patterns

### Reading Data
```ruby
# Controller can use Query directly
query = PoolAvailabilityQuery.new(account_id: 1, product_id: 2)
capacity = query.capacity_details
```

### Writing Data
```ruby
# Controller delegates to Service
service = Assignments::AssignWithAdvisoryLock.new(...)
result = service.call  # Service uses Queries internally
```

### Complex Operations
```ruby
# Service orchestrates multiple Queries + business logic
def call
  transaction do
    acquire_lock
    existing = ExistingHoldersQuery.new(...).user_ids
    available = PoolAvailabilityQuery.new(...).available_licenses
    # ... business logic ...
    LicenseAssignment.insert_all(...)
  end
end
```

## Further Reading

- [Service Objects in Rails](https://www.toptal.com/ruby-on-rails/rails-service-objects-tutorial)
- [Query Objects Pattern](https://medium.com/@blazejkosmowski/essential-rubyonrails-patterns-part-2-query-objects-4b253f4f4539)
- [PostgreSQL Advisory Locks](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS)
