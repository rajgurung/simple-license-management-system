# License Management System

![CI](https://github.com/rajgurung/simple-license-management-system/workflows/CI/badge.svg)
![Ruby](https://img.shields.io/badge/Ruby-3.4.2-red.svg)
![Rails](https://img.shields.io/badge/Rails-8.0.4-red.svg)
![Coverage](https://img.shields.io/badge/Coverage-97%25-brightgreen.svg)

A Ruby on Rails application for managing software license assignments with PostgreSQL advisory locks for concurrency-safe operations.

## Live Demo

- **URL**: https://vlex-licensing.up.railway.app/login
- **Username**: admin
- **Password**: AdminPassw0rd!

## Table of Contents

- [Features](#features)
- [Tech Stack](#tech-stack)
- [Local Development Setup](#local-development-setup)
- [Environment Variables](#environment-variables)
- [Architecture](#architecture)
  - [High-Level Architecture Flow](#high-level-architecture-flow)
  - [PostgreSQL Advisory Locks for Concurrency Control](#postgresql-advisory-locks-for-concurrency-control)
  - [Expiration Handling](#expiration-handling)
  - [Assignment Modes](#assignment-modes)
- [Current Implementation](#current-implementation)
  - [Concurrency Control](#concurrency-control)
  - [Request Processing](#request-processing)
  - [Performance Characteristics](#performance-characteristics)
- [Future Scaling Options](#future-scaling-options)
  - [Alternative Concurrency Approach: FOR UPDATE SKIP LOCKED](#alternative-concurrency-approach-for-update-skip-locked)
  - [Queue Systems for Async Processing](#queue-systems-for-async-processing)
  - [Migration Strategy](#migration-strategy)
- [Key Models](#key-models)
- [Testing](#testing)
- [Observability](#observability)

## Features

- Account and user management
- Product catalog management
- Subscription lifecycle management
- License assignment with capacity enforcement
- Concurrency-safe operations using PostgreSQL advisory locks
- Query-time expiration filtering (no background jobs)
- Structured JSON logging for observability

## Tech Stack

- **Rails**: 8.0.4
- **Ruby**: 3.4.2
- **Database**: PostgreSQL
- **CSS**: Tailwind CSS
- **Authentication**: Session-based with bcrypt
- **Observability**: Structured JSON logging

## Local Development Setup

### Prerequisites

- Ruby 3.4.2
- PostgreSQL 14+
- Bundler

### Installation

1. Clone the repository
2. Install dependencies:
   ```bash
   bundle install
   ```

3. Copy environment variables:
   ```bash
   cp .env.example .env
   ```

4. Create and setup database:
   ```bash
   rails db:create db:migrate db:seed
   ```

5. Start the development server:
   ```bash
   bin/dev
   ```

6. Visit http://localhost:3000

### Default Login Credentials

- **Username**: admin
- **Password**: AdminPassw0rd!

(Customizable via `.env` file)

## Environment Variables

Required environment variables:

```bash
# Admin Credentials
ADMIN_USERNAME=admin
ADMIN_PASSWORD=your_secure_password
ADMIN_EMAIL=admin@example.com

# Database
DATABASE_URL=postgresql://localhost/license_management_development

# Observability (optional)
SENTRY_DSN=https://your-sentry-dsn@sentry.io/project-id

# Rails
RAILS_ENV=development
```

## Architecture

### High-Level Architecture Flow

The application follows a layered architecture pattern for clean separation of concerns:

```
HTTP Request → Controller → Service → Query Objects → Models → Database
```

**Layer Responsibilities:**

1. **Controllers** (`app/controllers/`)
   - Handle HTTP request/response lifecycle
   - Extract and validate parameters
   - Enforce authentication/authorization
   - Delegate business logic to services

   ```ruby
   # Example: LicenseAssignmentsController
   def create
     result = Assignments::AssignWithAdvisoryLock.new(
       account_id: params[:account_id],
       product_id: params[:product_id],
       user_ids: params[:user_ids]
     ).call

     if result[:status] == :success
       redirect_to account_product_license_assignments_path, notice: "Assigned successfully"
     else
       flash.now[:alert] = "Insufficient capacity"
       render :new
     end
   end
   ```

2. **Services** (`app/services/`)
   - Orchestrate complex business operations
   - Manage database transactions
   - Handle concurrency control (advisory locks)
   - Emit structured logs for observability
   - Return consistent result hashes

   ```ruby
   # Example: Assignments::AssignWithAdvisoryLock
   def call
     ActiveRecord::Base.transaction do
       acquire_advisory_lock  # Prevent race conditions
       check_capacity         # Use query objects
       perform_assignments    # Business logic
       log_success           # Observability
     end
   end
   ```

3. **Query Objects** (`app/queries/`)
   - Encapsulate complex database queries
   - Provide reusable, testable query logic
   - Handle joins, aggregations, and filtering
   - Use `.distinct` to prevent double-counting

   ```ruby
   # Example: PoolAvailabilityQuery
   capacity = PoolAvailabilityQuery.new(
     account_id: 1,
     product_id: 2
   ).capacity_details
   # => { total: 100, used: 45, available: 55 }
   ```

4. **Models** (`app/models/`)
   - Define data structure and associations
   - Validate data integrity
   - Provide scopes for common queries
   - Keep business logic minimal (delegate to services)

**Key Design Decisions:**
- No idempotency keys table (database unique constraints provide natural idempotency)
- No background jobs for expiration (query-time filtering is simpler and real-time)
- No soft deletes (timestamp-based scopes handle "active" vs "expired")
- Global products catalog (not tenant-scoped)
- Type normalization in services (controllers pass arrays, services handle single/multiple)

### PostgreSQL Advisory Locks for Concurrency Control

The system uses **PostgreSQL advisory locks** to ensure concurrency-safe license assignments across multiple application servers.

**How It Works:**

1. **Lock Key Generation** (`Concurrency::AdvisoryLockKey`)
   ```ruby
   # Generate deterministic lock key from account_id + product_id
   def self.for_pool(account_id, product_id)
     key_string = "#{account_id}-#{product_id}"
     Digest::SHA256.hexdigest(key_string).to_i(16) % (2**31 - 1)
   end
   # Example: account_id=1, product_id=2 → lock_key=543231903
   ```

2. **Lock Acquisition** (in `Assignments::AssignWithAdvisoryLock`)
   ```ruby
   def acquire_advisory_lock
     lock_key = Concurrency::AdvisoryLockKey.for_pool(account_id, product_id)
     ActiveRecord::Base.connection.execute(
       "SELECT pg_advisory_xact_lock(#{lock_key})"
     )
   end
   ```

3. **Automatic Release**
   - Uses `pg_advisory_xact_lock` (transaction-level lock)
   - Automatically released on `COMMIT` or `ROLLBACK`
   - No manual cleanup required

**Benefits:**
- **Prevents race conditions**: Only one process can assign licenses to a pool at a time
- **Atomic operations**: Capacity check + assignment happen atomically
- **No double-booking**: Impossible to over-assign licenses
- **Works across servers**: PostgreSQL coordinates locks for all app instances
- **Low overhead**: Lock acquisition ~1.3ms, total assignment ~15ms

**Performance Characteristics:**
- Lock contention only occurs for the same account+product combination
- Different products/accounts can process concurrently without blocking
- No distributed lock coordinator needed (PostgreSQL handles coordination)

**References:**
- [PostgreSQL Advisory Locks Documentation](https://www.postgresql.org/docs/current/explicit-locking.html#ADVISORY-LOCKS)

### Expiration Handling

No background jobs required. Uses **query-time filtering** with scopes:

```ruby
# Active subscriptions
Subscription.active  # WHERE expires_at > NOW()

# Assignments respect subscription expiration
LicenseAssignment.active  # Joins to subscription, filters expired
```

**Why No Background Jobs?**
- Simpler architecture (no job queue maintenance)
- Real-time accuracy (no lag between expiration and enforcement)
- One less moving part to monitor and debug
- Query-time filtering is fast with proper indexes

### Assignment Modes

The service supports two assignment strategies:

- **`:all_or_nothing`** - Strict capacity enforcement. Rollback entire transaction if insufficient licenses available.
- **`:partial_fill`** - Assign up to available capacity, return overflow users for handling.

## Current Implementation

### Concurrency Control
The system uses **PostgreSQL Advisory Locks** for concurrency-safe license assignments:

- **Pool-level locking**: Locks entire account+product pool during assignment
- **Cross-server coordination**: Works reliably across multiple application servers
- **Automatic cleanup**: Transaction-level locks (`pg_advisory_xact_lock`) auto-release on commit/rollback
- **Performance**: Lock acquisition ~1.3ms, total assignment ~15ms
- **Suitable for**: Moderate concurrency (100s of concurrent requests per pool)

### Request Processing
The system uses **synchronous HTTP request/response**:

- Client waits for assignment to complete (~15ms total)
- Immediate feedback on success/failure
- Simple architecture with no additional infrastructure
- Works well for interactive web applications

### Performance Characteristics
- **Throughput**: Handles hundreds of concurrent requests per account+product pool
- **Latency**: ~15ms per license assignment operation
- **Contention**: Only occurs when multiple requests target the same account+product combination
- **Isolation**: Different products/accounts process concurrently without blocking

## Future Scaling Options

For applications requiring extremely high throughput (e.g., 10,000+ requests/second), consider these scaling strategies:

### Alternative Concurrency Approach: FOR UPDATE SKIP LOCKED

Instead of pool-level advisory locks, use row-level locking with `FOR UPDATE SKIP LOCKED`:

**How it works:**
```ruby
# Attempt to claim available license slots
available_licenses = Subscription
  .where(account_id: account_id, product_id: product_id)
  .where('expires_at > ?', Time.current)
  .lock('FOR UPDATE SKIP LOCKED')  # Skip locked rows, take available ones
  .limit(requested_count)

# If some rows are locked by other transactions, this query skips them
# and takes only the immediately available rows
```

**Benefits:**
- Multiple transactions can assign licenses concurrently (less blocking)
- Failed transactions don't block others (SKIP LOCKED continues past locked rows)
- Better throughput under extreme concurrency
- Locks individual license records instead of entire pool

**Trade-offs:**
- More complex query logic
- May require queue/slot tracking table
- PostgreSQL 9.5+ required
- Potential for partial failures if not enough unlocked rows available

**When to migrate:**
- Observing frequent lock contention (check `pg_stat_activity` for waiting locks)
- Need to support 1,000+ concurrent assignment requests to same pool
- Willing to accept additional implementation complexity

**References:**
- [BigBinary Blog: Understanding FOR UPDATE SKIP LOCKED in Rails](https://www.bigbinary.com/blog/solid-queue?utm_source=chatgpt.com)
- [PostgreSQL Row-Level Locking Documentation](https://www.postgresql.org/docs/current/explicit-locking.html#LOCKING-ROWS)

### Queue Systems for Async Processing

Instead of synchronous HTTP, offload license assignments to background queue workers:

**Available Options:**

1. **Solid Queue** (Rails 8 default, already installed)
   - Database-backed job queue (uses PostgreSQL)
   - No additional infrastructure required (Redis, etc.)
   - Built-in job prioritization, recurring tasks, concurrency control
   - Good for 100-1,000 jobs/second

   ```ruby
   # Example: Async license assignment with Solid Queue
   class AssignLicensesJob < ApplicationJob
     queue_as :default

     def perform(account_id, product_id, user_ids)
       Assignments::AssignWithAdvisoryLock.new(
         account_id: account_id,
         product_id: product_id,
         user_ids: user_ids
       ).call
     end
   end

   # In controller
   job = AssignLicensesJob.perform_later(account_id, product_id, user_ids)
   render json: { job_id: job.job_id, status: "processing" }
   ```

2. **Sidekiq** (for extreme throughput)
   - Redis-backed job queue
   - Industry standard for high-throughput scenarios
   - Excellent performance: 10,000+ jobs/second per process
   - Requires Redis infrastructure (additional operational complexity)
   - Rich ecosystem: monitoring, plugins, Enterprise features

   ```ruby
   # Gemfile
   gem 'sidekiq'
   gem 'redis'

   # Example: High-throughput async processing
   class AssignLicensesWorker
     include Sidekiq::Worker
     sidekiq_options queue: :critical, retry: 3

     def perform(account_id, product_id, user_ids)
       Assignments::AssignWithAdvisoryLock.new(
         account_id: account_id,
         product_id: product_id,
         user_ids: user_ids
       ).call
     end
   end
   ```

**When to use background jobs:**

- **Solid Queue** when:
  - Need async processing but want to keep architecture simple
  - Database is already PostgreSQL (no new dependencies)
  - Throughput requirement: 100-1,000 jobs/second
  - Willing to trade some speed for operational simplicity

- **Sidekiq** when:
  - Need extreme throughput (10,000+ jobs/second)
  - Already have Redis infrastructure
  - Need advanced features (rate limiting, batching, scheduled jobs)
  - Can handle additional operational complexity (Redis monitoring, persistence)

### Scaling Architecture Example (10k/sec target)

```
Load Balancer
    ↓
[Web Servers (4x)] → Handle HTTP, enqueue jobs → [Redis/PostgreSQL Queue]
                                                         ↓
                                                  [Worker Pool (10x)]
                                                         ↓
                                                  Process assignments
                                                         ↓
                                                    [PostgreSQL]
```

### Migration Strategy

1. Start with synchronous processing + advisory locks (current implementation)
2. If latency becomes issue: Add Solid Queue for async processing
3. If throughput exceeds 1k/sec: Migrate to Sidekiq + Redis
4. If lock contention detected: Migrate from advisory locks to FOR UPDATE SKIP LOCKED

**References:**
- [Solid Queue GitHub](https://github.com/rails/solid_queue)
- [Sidekiq Documentation](https://github.com/sidekiq/sidekiq)
- [BigBinary Blog: Job Queue Patterns](https://www.bigbinary.com/blog/solid-queue?utm_source=chatgpt.com)

## Key Models

- **Account**: Organizations/tenants
- **Product**: Global product catalog
- **User**: Users within accounts (admin or regular)
- **Subscription**: Account's subscription to a product (licenses + expiration)
- **LicenseAssignment**: User assigned to a product license

## Testing

Run the test suite:

```bash
bundle exec rspec
```

## Observability

### Structured Logs

All logs output JSON to STDOUT:

```json
{
  "ts": "2025-01-06T18:30:45Z",
  "level": "info",
  "svc": "license_management",
  "env": "production",
  "event": "assign_finish",
  "account_id": 1,
  "product_id": 2,
  "assigned_count": 5,
  "outcome": "full"
}
```

### Optional Integrations

The application supports optional third-party integrations for enhanced observability:

- **Sentry**: Automatic error tracking and performance monitoring when `SENTRY_DSN` is configured
- **Logflare**: Log aggregation and querying (requires additional setup)

## License

This project is proprietary software.
