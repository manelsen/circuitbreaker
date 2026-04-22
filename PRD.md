# PRD — `circuit_breaker`

## Visão

Implementação idiomática do padrão circuit breaker para Gleam, com estado puro separado de gestão OTP. Qualquer aplicação Gleam que chame serviços externos (APIs, banco de dados, filas) pode usar este pacote para evitar cascata de falhas sem depender de uma stack específica.

## Problema

Aplicações Gleam que chamam serviços externos não têm um primitivo de resiliência padronizado. Cada projeto implementa sua própria lógica de retry ou circuit breaker, resultando em implementações inconsistentes, sem testes e acopladas ao domínio. O ecossistema não tem nada equivalente ao `fuse` do Erlang ou ao `Polly` do .NET para Gleam idiomático.

## Público-alvo

Desenvolvedores Gleam construindo aplicações que integram com serviços externos: APIs HTTP, bancos de dados, message brokers, microserviços. Nível: intermediário — sabe usar `gleam_otp` e entende o modelo de processos.

## Escopo da v1.0

**Entra:**
- Máquina de estados pura: `CircuitClosed → CircuitOpen → CircuitHalfOpen`
- Actor OTP thread-safe para múltiplas chaves independentes
- Registro global opcional via `persistent_term`
- Documentação completa com exemplos executáveis
- Testes cobrindo todos os módulos

**Não entra na v1.0:**
- Sliding window para contagem de falhas (usa contador simples)
- Métricas ou telemetria embutida
- Integração automática com HTTP clients

---

## Problemas a resolver antes da publicação

### P1 — Unificação do tipo de configuração (bloqueador de API)

**Problema:** `circuit_breaker.CircuitConfig` e `circuit_breaker/actor.CircuitBreakerConfig` têm os mesmos três campos e exigem que o usuário construa dois objetos distintos.

**Decisão:** Remover `CircuitBreakerConfig` do actor. O `actor.start` passa a aceitar `circuit_breaker.CircuitConfig` diretamente.

```gleam
// Antes (dois tipos, confuso)
let cb_config = actor.CircuitBreakerConfig(failure_threshold: 5, ...)
let assert Ok(cb) = actor.start(cb_config)

// Depois (um tipo, consistente)
let config = circuit_breaker.CircuitConfig(failure_threshold: 5, ...)
let assert Ok(cb) = actor.start(config)
```

### P2 — `PubSubMessage` (aka `CircuitBreakerCommand`) exposto

**Problema:** `CircuitBreakerCommand` é `pub` e vaza detalhes de implementação do actor.

**Decisão:** Tornar `CircuitBreakerCommand` opaco ou trocar para `pub(internal)`. Usuários interagem apenas via `check_and_call`, `record_success`, `record_failure`, `get_state`, `stop`.

### P3 — Testes do actor e do global (cobertura)

**Problema:** `actor.gleam` e `global.gleam` não têm testes. As funções `start`, `check_and_call`, `get_state`, `stop` e todo o módulo `global` são exercitados apenas em produção.

**Testes a criar em `test/circuit_breaker/actor_test.gleam`:**
- `start_with_valid_config_test` — actor inicia sem erro
- `check_returns_allowed_when_closed_test`
- `check_returns_blocked_after_failures_test`
- `get_state_reflects_transitions_test`
- `stop_terminates_actor_test`
- `concurrent_keys_are_independent_test`

**Testes a criar em `test/circuit_breaker/global_test.gleam`:**
- `get_returns_none_before_set_test`
- `set_and_get_returns_actor_test`
- `get_returns_none_after_actor_dies_test`

---

## API pública alvo para v1.0

```gleam
// circuit_breaker.gleam
pub fn new(name: String, config: CircuitConfig) -> CircuitBreaker
pub fn is_call_allowed(breaker: CircuitBreaker, config: CircuitConfig) -> Bool
pub fn record_success(breaker: CircuitBreaker, config: CircuitConfig) -> CircuitBreaker
pub fn record_failure(breaker: CircuitBreaker, config: CircuitConfig) -> CircuitBreaker
pub fn state_name(state: CircuitState) -> String

// circuit_breaker/actor.gleam
pub fn start(config: circuit_breaker.CircuitConfig) -> Result(CircuitBreakerActor, actor.StartError)
pub fn start_linked(config: circuit_breaker.CircuitConfig) -> Result(actor.Started(CircuitBreakerActor), actor.StartError)
pub fn check_and_call(cb: CircuitBreakerActor, key: String) -> CheckResult
pub fn record_success(cb: CircuitBreakerActor, key: String) -> Nil
pub fn record_failure(cb: CircuitBreakerActor, key: String) -> Nil
pub fn get_state(cb: CircuitBreakerActor, key: String) -> circuit_breaker.CircuitState
pub fn stop(cb: CircuitBreakerActor) -> Nil

// circuit_breaker/global.gleam
pub fn set(cb: CircuitBreakerActor) -> Nil
pub fn get() -> Option(CircuitBreakerActor)
pub fn check_and_call(key: String) -> CheckResult
pub fn record_success(key: String) -> Nil
pub fn record_failure(key: String) -> Nil
```

---

## Critérios de aceitação para publicação

- [ ] `gleam.toml`: `user` preenchido, `links` com URL do repositório
- [ ] `README.md` com: descrição em uma frase, instalação, exemplo completo executável, diagrama de estados em texto
- [ ] `CircuitBreakerConfig` removido — actor aceita `circuit_breaker.CircuitConfig`
- [ ] `CircuitBreakerCommand` não exposto na API pública
- [ ] Testes para `actor.gleam`: mínimo 6 casos
- [ ] Testes para `global.gleam`: mínimo 3 casos
- [ ] Total de testes: ≥ 17 (8 existentes + 9 novos)
- [ ] `gleam docs build` sem erros — todas as funções públicas com doc comment
- [ ] CI: `.github/workflows/test.yml` rodando `gleam test` em push e pull request
- [ ] `gleam test` verde

## Pendências de decisão

- **Nome de `check_and_call`:** o nome sugere execução, mas a função só verifica. Avaliar renomear para `check` com retorno `CheckResult`.
- **`state_name` vs pattern matching:** a função `state_name` converte estado em string, mas em Gleam o pattern matching direto seria mais idiomático. Considerar remover e deixar os tipos falarem.
