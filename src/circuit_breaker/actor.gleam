//// Circuit breaker OTP actor.
////
//// Manages per-key circuit breakers with thread-safe actor-based state.
////
//// ## Usage
////
//// ```gleam
//// let config = circuit_breaker.CircuitConfig(
////   failure_threshold: 5,
////   recovery_timeout_ms: 30_000,
////   half_open_max_calls: 2,
//// )
//// let assert Ok(cb) = actor.start(config)
////
//// case actor.check_and_call(cb, "my_service") {
////   actor.Allowed  -> // proceed
////   actor.Blocked(_) -> // fail fast
//// }
////
//// actor.record_success(cb, "my_service")
//// actor.record_failure(cb, "my_service")
//// ```

import circuit_breaker
import gleam/dict
import gleam/erlang/process.{type Subject}
import gleam/otp/actor

pub type CircuitBreakerActor =
  Subject(CircuitBreakerCommand)

pub opaque type CircuitBreakerCommand {
  CheckAndCall(key: String, reply_to: Subject(CheckResult))
  RecordSuccess(key: String, reply_to: Subject(Nil))
  RecordFailure(key: String, reply_to: Subject(Nil))
  GetState(key: String, reply_to: Subject(circuit_breaker.CircuitState))
  Stop(reply_to: Subject(Nil))
}

pub type CheckResult {
  Allowed
  Blocked(reason: String)
}

type BreakerMap =
  dict.Dict(String, circuit_breaker.CircuitBreaker)

fn handle_message(
  state: BreakerMap,
  message: CircuitBreakerCommand,
  config: circuit_breaker.CircuitConfig,
) -> actor.Next(BreakerMap, CircuitBreakerCommand) {
  case message {
    CheckAndCall(key, reply_to) -> {
      let breaker = get_or_create(state, key, config)
      case circuit_breaker.is_call_allowed(breaker, config) {
        True -> actor.send(reply_to, Allowed)
        False -> actor.send(reply_to, Blocked("circuit_open"))
      }
      actor.continue(state)
    }
    RecordSuccess(key, reply_to) -> {
      let breaker = get_or_create(state, key, config)
      let updated = circuit_breaker.record_success(breaker, config)
      actor.send(reply_to, Nil)
      actor.continue(dict.insert(state, key, updated))
    }
    RecordFailure(key, reply_to) -> {
      let breaker = get_or_create(state, key, config)
      let updated = circuit_breaker.record_failure(breaker, config)
      actor.send(reply_to, Nil)
      actor.continue(dict.insert(state, key, updated))
    }
    GetState(key, reply_to) -> {
      let breaker = get_or_create(state, key, config)
      actor.send(reply_to, breaker.state)
      actor.continue(state)
    }
    Stop(reply_to) -> {
      actor.send(reply_to, Nil)
      actor.stop()
    }
  }
}

fn get_or_create(
  state: BreakerMap,
  key: String,
  config: circuit_breaker.CircuitConfig,
) -> circuit_breaker.CircuitBreaker {
  case dict.get(state, key) {
    Ok(breaker) -> breaker
    Error(_) -> circuit_breaker.new(key, config)
  }
}

/// Start a circuit breaker actor with the given config.
pub fn start(
  config: circuit_breaker.CircuitConfig,
) -> Result(CircuitBreakerActor, actor.StartError) {
  case start_linked(config) {
    Ok(started) -> Ok(started.data)
    Error(e) -> Error(e)
  }
}

/// Start and return the full Started record (for use with supervisors).
pub fn start_linked(
  config: circuit_breaker.CircuitConfig,
) -> Result(actor.Started(CircuitBreakerActor), actor.StartError) {
  actor.new(dict.new())
  |> actor.on_message(fn(state, message) {
    handle_message(state, message, config)
  })
  |> actor.start
}

/// Check whether a call is allowed for the given key.
pub fn check_and_call(cb: CircuitBreakerActor, key: String) -> CheckResult {
  actor.call(cb, waiting: 5000, sending: CheckAndCall(key, _))
}

/// Record a successful call for the given key.
pub fn record_success(cb: CircuitBreakerActor, key: String) -> Nil {
  actor.call(cb, waiting: 5000, sending: RecordSuccess(key, _))
}

/// Record a failed call for the given key.
pub fn record_failure(cb: CircuitBreakerActor, key: String) -> Nil {
  actor.call(cb, waiting: 5000, sending: RecordFailure(key, _))
}

/// Return the current circuit state for the given key.
pub fn get_state(
  cb: CircuitBreakerActor,
  key: String,
) -> circuit_breaker.CircuitState {
  actor.call(cb, waiting: 5000, sending: GetState(key, _))
}

/// Stop the actor.
pub fn stop(cb: CircuitBreakerActor) -> Nil {
  actor.call(cb, waiting: 5000, sending: Stop)
}
