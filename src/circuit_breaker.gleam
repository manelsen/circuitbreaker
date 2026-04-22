//// Circuit breaker — closed, open, half-open state machine.
////
//// Implements the classic circuit breaker pattern for fault tolerance.
//// Transitions: Closed (normal) → Open (failing) → HalfOpen (recovering).
////
//// ## Usage
////
//// ```gleam
//// let config = circuit_breaker.CircuitConfig(
////   failure_threshold: 5,
////   recovery_timeout_ms: 30_000,
////   half_open_max_calls: 2,
//// )
//// let cb = circuit_breaker.new("my_service", config)
////
//// // Before calling the service:
//// case circuit_breaker.is_call_allowed(cb, config) {
////   True  -> // proceed
////   False -> // fail fast
//// }
////
//// // After success / failure:
//// let cb = circuit_breaker.record_success(cb, config)
//// let cb = circuit_breaker.record_failure(cb, config)
//// ```

pub type CircuitBreaker {
  CircuitBreaker(
    name: String,
    state: CircuitState,
    failure_count: Int,
    success_count: Int,
    last_failure_time_ms: Int,
    cooldown_ms: Int,
  )
}

pub type CircuitState {
  CircuitClosed
  CircuitOpen
  CircuitHalfOpen
}

pub type CircuitConfig {
  CircuitConfig(
    failure_threshold: Int,
    recovery_timeout_ms: Int,
    half_open_max_calls: Int,
  )
}

@external(erlang, "circuit_breaker_ffi", "current_timestamp")
fn current_timestamp() -> Int

/// Create a new circuit breaker in the Closed state.
pub fn new(name: String, config: CircuitConfig) -> CircuitBreaker {
  CircuitBreaker(
    name: name,
    state: CircuitClosed,
    failure_count: 0,
    success_count: 0,
    last_failure_time_ms: 0,
    cooldown_ms: config.recovery_timeout_ms,
  )
}

/// Returns True if the circuit allows a call through.
///
/// - Closed: always allowed.
/// - Open: allowed only after the recovery timeout has elapsed (transitions to HalfOpen).
/// - HalfOpen: allowed while success_count < half_open_max_calls.
pub fn is_call_allowed(breaker: CircuitBreaker, config: CircuitConfig) -> Bool {
  let now = current_timestamp()
  case breaker.state {
    CircuitClosed -> True
    CircuitOpen ->
      now - breaker.last_failure_time_ms >= config.recovery_timeout_ms
    CircuitHalfOpen -> breaker.success_count < config.half_open_max_calls
  }
}

/// Record a successful call. Transitions HalfOpen → Closed once enough successes.
pub fn record_success(
  breaker: CircuitBreaker,
  config: CircuitConfig,
) -> CircuitBreaker {
  case breaker.state {
    CircuitClosed ->
      CircuitBreaker(
        ..breaker,
        failure_count: 0,
        success_count: breaker.success_count + 1,
      )
    CircuitHalfOpen -> {
      let new_success = breaker.success_count + 1
      case new_success >= config.half_open_max_calls {
        True ->
          CircuitBreaker(
            ..breaker,
            state: CircuitClosed,
            failure_count: 0,
            success_count: 0,
          )
        False -> CircuitBreaker(..breaker, success_count: new_success)
      }
    }
    CircuitOpen -> breaker
  }
}

/// Record a failed call. Transitions Closed → Open at threshold, HalfOpen → Open immediately.
pub fn record_failure(
  breaker: CircuitBreaker,
  config: CircuitConfig,
) -> CircuitBreaker {
  let now = current_timestamp()
  let new_failures = breaker.failure_count + 1
  case breaker.state {
    CircuitClosed ->
      case new_failures >= config.failure_threshold {
        True ->
          CircuitBreaker(
            ..breaker,
            state: CircuitOpen,
            failure_count: new_failures,
            success_count: 0,
            last_failure_time_ms: now,
          )
        False ->
          CircuitBreaker(
            ..breaker,
            failure_count: new_failures,
            last_failure_time_ms: now,
          )
      }
    CircuitHalfOpen ->
      CircuitBreaker(
        ..breaker,
        state: CircuitOpen,
        failure_count: 1,
        success_count: 0,
        last_failure_time_ms: now,
      )
    CircuitOpen -> breaker
  }
}

/// Return the state name as a string.
pub fn state_name(state: CircuitState) -> String {
  case state {
    CircuitClosed -> "closed"
    CircuitOpen -> "open"
    CircuitHalfOpen -> "half_open"
  }
}
