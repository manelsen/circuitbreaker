# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands

```bash
gleam build          # compile
gleam test           # run all tests (gleeunit/EUnit)
gleam format         # format all Gleam source files
gleam docs build     # build HTML docs (all public functions must have doc comments)
```

To run a single test function, invoke EUnit directly after building:

```bash
gleam build && erl -pa build/dev/erlang/*/ebin -eval "eunit:test({circuit_breaker_test, new_breaker_starts_closed_test}, [verbose]), init:stop()."
```

## Architecture

Three-layer design: pure state machine → OTP actor → global registry.

**`src/circuit_breaker.gleam`** — pure, immutable state machine. No processes. `CircuitBreaker` is a plain record holding `state`, `failure_count`, `success_count`, `last_failure_time_ms`. Transitions: `CircuitClosed → CircuitOpen → CircuitHalfOpen → CircuitClosed`. Core functions: `new`, `is_call_allowed`, `record_success`, `record_failure`. Calls the Erlang FFI (`circuit_breaker_ffi.erl`) only for `erlang:system_time(millisecond)`.

**`src/circuit_breaker/actor.gleam`** — OTP actor wrapping the state machine. Manages a `Dict(String, CircuitBreaker)` so one actor instance tracks multiple independent keys. Commands (`CircuitBreakerCommand`) are sent via `actor.call` with a 5 s timeout. `start` returns the `Subject`; `start_linked` returns the full `Started` record for supervisor trees.

**`src/circuit_breaker/global.gleam`** — optional node-wide registry using Erlang `persistent_term` (via `circuit_breaker_global_ffi.erl`). `set/1` stores a `CircuitBreakerActor` subject; `get/0` returns `Option(CircuitBreakerActor)` after checking `is_process_alive`. Functions fall back to `Allowed`/`Nil` when no global instance is registered.

**Erlang FFI files** (`src/*.erl`) are compiled alongside Gleam. They are not generated — edit them directly when the FFI surface needs to change.

## Known issues (from PRD.md — resolve before publishing to Hex)

- **P1 (blocking):** `actor.CircuitBreakerConfig` duplicates `circuit_breaker.CircuitConfig`. `actor.start`/`start_linked` should accept `circuit_breaker.CircuitConfig` directly and `CircuitBreakerConfig` should be removed.
- **P2:** `CircuitBreakerCommand` is `pub` and leaks actor internals. It should be `pub(internal)` or opaque.
- **P3:** No tests for `actor.gleam` or `global.gleam`. Target: ≥ 6 actor tests in `test/circuit_breaker/actor_test.gleam` and ≥ 3 global tests in `test/circuit_breaker/global_test.gleam`.
- `gleam.toml` fields `repository.user` and `links` are empty — fill before publishing.
- `actor.gleam` doc example still references `actor.CircuitBreakerConfig` (stale after P1 fix).
