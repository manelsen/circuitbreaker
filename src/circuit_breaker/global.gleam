//// Global circuit breaker registry via persistent_term.
////
//// Stores the circuit breaker actor in a node-wide registry so it can
//// be retrieved from any process without passing it explicitly.
////
//// ## Usage
////
//// ```gleam
//// let assert Ok(cb) = actor.start(config)
//// global.set(cb)
////
//// // From anywhere:
//// global.check_and_call("my_service")
//// global.record_failure("my_service")
//// ```

import circuit_breaker/actor as cb_actor
import gleam/erlang/process.{type Subject}
import gleam/option

pub type CircuitBreaker =
  Subject(cb_actor.CircuitBreakerCommand)

@external(erlang, "circuit_breaker_global_ffi", "global_put")
fn global_put(key: String, value: a) -> Nil

@external(erlang, "circuit_breaker_global_ffi", "global_get")
fn global_get(key: String) -> a

@external(erlang, "circuit_breaker_global_ffi", "global_has")
fn global_has(key: String) -> Bool

@external(erlang, "circuit_breaker_global_ffi", "global_delete")
fn global_delete(key: String) -> Nil

@external(erlang, "circuit_breaker_global_ffi", "safe_is_process_alive")
fn safe_check_alive(pid: a) -> Bool

const registry_key = "circuit_breaker_global"

/// Register the circuit breaker actor as the global instance.
pub fn set(cb: CircuitBreaker) -> Nil {
  global_put(registry_key, cb)
}

/// Retrieve the global circuit breaker actor, if alive.
pub fn get() -> option.Option(CircuitBreaker) {
  case global_has(registry_key) {
    True -> {
      let cb = global_get(registry_key)
      case safe_check_alive(cb) {
        True -> option.Some(cb)
        False -> option.None
      }
    }
    False -> option.None
  }
}

/// Remove the global circuit breaker instance.
pub fn clear() -> Nil {
  global_delete(registry_key)
}

/// Check whether a call is allowed, using the global instance.
/// Returns Allowed if no global circuit breaker is registered.
pub fn check_and_call(key: String) -> cb_actor.CheckResult {
  case get() {
    option.Some(cb) -> cb_actor.check_and_call(cb, key)
    option.None -> cb_actor.Allowed
  }
}

pub fn record_success(key: String) -> Nil {
  case get() {
    option.Some(cb) -> cb_actor.record_success(cb, key)
    option.None -> Nil
  }
}

pub fn record_failure(key: String) -> Nil {
  case get() {
    option.Some(cb) -> cb_actor.record_failure(cb, key)
    option.None -> Nil
  }
}
