import circuit_breaker
import circuit_breaker/actor
import gleam/erlang/process
import gleeunit/should

fn config() -> circuit_breaker.CircuitConfig {
  circuit_breaker.CircuitConfig(
    failure_threshold: 3,
    recovery_timeout_ms: 50,
    half_open_max_calls: 2,
  )
}

pub fn start_with_valid_config_test() {
  let assert Ok(cb) = actor.start(config())
  actor.stop(cb)
}

pub fn check_returns_allowed_when_closed_test() {
  let assert Ok(cb) = actor.start(config())
  actor.check_and_call(cb, "svc") |> should.equal(actor.Allowed)
  actor.stop(cb)
}

pub fn check_returns_blocked_after_failures_test() {
  let assert Ok(cb) = actor.start(config())
  actor.record_failure(cb, "svc")
  actor.record_failure(cb, "svc")
  actor.record_failure(cb, "svc")
  actor.check_and_call(cb, "svc")
  |> should.equal(actor.Blocked("circuit_open"))
  actor.stop(cb)
}

pub fn get_state_reflects_transitions_test() {
  let assert Ok(cb) = actor.start(config())
  actor.get_state(cb, "svc") |> should.equal(circuit_breaker.CircuitClosed)
  actor.record_failure(cb, "svc")
  actor.record_failure(cb, "svc")
  actor.record_failure(cb, "svc")
  actor.get_state(cb, "svc") |> should.equal(circuit_breaker.CircuitOpen)
  actor.stop(cb)
}

pub fn stop_terminates_actor_test() {
  let assert Ok(cb) = actor.start(config())
  let assert Ok(pid) = process.subject_owner(cb)
  actor.stop(cb)
  process.sleep(10)
  process.is_alive(pid) |> should.be_false
}

pub fn concurrent_keys_are_independent_test() {
  let assert Ok(cb) = actor.start(config())
  actor.record_failure(cb, "svc_a")
  actor.record_failure(cb, "svc_a")
  actor.record_failure(cb, "svc_a")
  actor.check_and_call(cb, "svc_a")
  |> should.equal(actor.Blocked("circuit_open"))
  actor.check_and_call(cb, "svc_b") |> should.equal(actor.Allowed)
  actor.stop(cb)
}
