# circuit_breaker

[![test](https://github.com/manelsen/circuitbreaker/actions/workflows/test.yml/badge.svg)](https://github.com/manelsen/circuitbreaker/actions/workflows/test.yml)

Circuit breaker for Gleam — closed, open, half-open states with OTP actor support.

## Installation

```sh
gleam add circuit_breaker
```

## Usage

### Pure state machine

For applications that manage their own state, use `circuit_breaker` directly:

```gleam
import circuit_breaker

let config = circuit_breaker.CircuitConfig(
  failure_threshold: 5,
  recovery_timeout_ms: 30_000,
  half_open_max_calls: 2,
)

let cb = circuit_breaker.new("my_service", config)

let cb = case circuit_breaker.is_call_allowed(cb, config) {
  True ->
    case call_my_service() {
      Ok(_) -> circuit_breaker.record_success(cb, config)
      Error(_) -> circuit_breaker.record_failure(cb, config)
    }
  False -> cb
}
```

### OTP actor (thread-safe, multi-key)

For concurrent applications, use the actor — one instance manages multiple independent keys:

```gleam
import circuit_breaker
import circuit_breaker/actor

let config = circuit_breaker.CircuitConfig(
  failure_threshold: 5,
  recovery_timeout_ms: 30_000,
  half_open_max_calls: 2,
)

let assert Ok(cb) = actor.start(config)

case actor.check_and_call(cb, "my_service") {
  actor.Allowed ->
    case call_my_service() {
      Ok(_) -> actor.record_success(cb, "my_service")
      Error(_) -> actor.record_failure(cb, "my_service")
    }
  actor.Blocked(_) -> Nil
}
```

### Global registry

When you can't pass the actor subject through the call stack:

```gleam
import circuit_breaker/actor
import circuit_breaker/global

// At application startup:
let assert Ok(cb) = actor.start(config)
global.set(cb)

// From anywhere:
case global.check_and_call("my_service") {
  actor.Allowed -> // proceed
  actor.Blocked(_) -> // fail fast
}
```

## State transitions

```
Closed ──[failures ≥ threshold]──► Open
  ▲                                  │
  │                              [timeout]
  │                                  ▼
  └──[successes ≥ max_calls]──── HalfOpen ──[any failure]──► Open
```

| State    | Behaviour                                                         |
|----------|-------------------------------------------------------------------|
| Closed   | Normal operation; all calls pass through                          |
| Open     | Circuit tripped; calls rejected immediately (fail fast)           |
| HalfOpen | Recovery probe; limited calls allowed to test the downstream      |
