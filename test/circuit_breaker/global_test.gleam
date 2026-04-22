import circuit_breaker
import circuit_breaker/actor
import circuit_breaker/global
import gleam/erlang/process
import gleeunit/should

fn config() -> circuit_breaker.CircuitConfig {
  circuit_breaker.CircuitConfig(
    failure_threshold: 3,
    recovery_timeout_ms: 50,
    half_open_max_calls: 2,
  )
}

pub fn get_returns_none_before_set_test() {
  global.clear()
  global.get() |> should.be_none
}

pub fn set_and_get_returns_actor_test() {
  global.clear()
  let assert Ok(cb) = actor.start(config())
  global.set(cb)
  global.get() |> should.be_some
  actor.stop(cb)
}

pub fn get_returns_none_after_actor_dies_test() {
  global.clear()
  let assert Ok(cb) = actor.start(config())
  global.set(cb)
  actor.stop(cb)
  process.sleep(10)
  global.get() |> should.be_none
}
