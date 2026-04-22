import circuit_breaker as cb
import gleam/option.{Some}
import gleeunit
import gleeunit/should

pub fn main() {
  gleeunit.main()
}

fn config() -> cb.CircuitConfig {
  cb.CircuitConfig(
    failure_threshold: 2,
    recovery_timeout_ms: 1000,
    half_open_max_calls: 2,
  )
}

pub fn new_breaker_starts_closed_test() {
  let breaker = cb.new("svc", config())
  breaker.state |> should.equal(cb.CircuitClosed)
  breaker.failure_count |> should.equal(0)
  breaker.success_count |> should.equal(0)
}

pub fn failure_below_threshold_stays_closed_test() {
  let breaker = cb.new("svc", config())
  let next = cb.record_failure(breaker, config())
  next.state |> should.equal(cb.CircuitClosed)
  next.failure_count |> should.equal(1)
}

pub fn failure_at_threshold_opens_circuit_test() {
  let breaker =
    cb.CircuitBreaker(
      name: "svc",
      state: cb.CircuitClosed,
      failure_count: 1,
      success_count: 0,
      last_failure_time_ms: 0,
      cooldown_ms: 1000,
    )
  let next = cb.record_failure(breaker, config())
  next.state |> should.equal(cb.CircuitOpen)
  next.failure_count |> should.equal(2)
}

pub fn open_before_timeout_blocks_calls_test() {
  let breaker =
    cb.CircuitBreaker(
      name: "svc",
      state: cb.CircuitOpen,
      failure_count: 2,
      success_count: 0,
      last_failure_time_ms: 9_999_999_999_999,
      cooldown_ms: 1000,
    )
  cb.is_call_allowed(breaker, config()) |> should.equal(False)
}

pub fn open_after_timeout_allows_calls_test() {
  let breaker =
    cb.CircuitBreaker(
      name: "svc",
      state: cb.CircuitOpen,
      failure_count: 2,
      success_count: 0,
      last_failure_time_ms: 0,
      cooldown_ms: 1000,
    )
  cb.is_call_allowed(breaker, config()) |> should.equal(True)
}

pub fn half_open_success_at_limit_closes_circuit_test() {
  let breaker =
    cb.CircuitBreaker(
      name: "svc",
      state: cb.CircuitHalfOpen,
      failure_count: 0,
      success_count: 1,
      last_failure_time_ms: 0,
      cooldown_ms: 1000,
    )
  let next = cb.record_success(breaker, config())
  next.state |> should.equal(cb.CircuitClosed)
  next.success_count |> should.equal(0)
}

pub fn half_open_failure_reopens_circuit_test() {
  let breaker =
    cb.CircuitBreaker(
      name: "svc",
      state: cb.CircuitHalfOpen,
      failure_count: 0,
      success_count: 1,
      last_failure_time_ms: 0,
      cooldown_ms: 1000,
    )
  let next = cb.record_failure(breaker, config())
  next.state |> should.equal(cb.CircuitOpen)
}

pub fn state_name_test() {
  cb.state_name(cb.CircuitClosed) |> should.equal("closed")
  cb.state_name(cb.CircuitOpen) |> should.equal("open")
  cb.state_name(cb.CircuitHalfOpen) |> should.equal("half_open")
  Some(cb.new("svc", config()).name) |> should.equal(Some("svc"))
}
