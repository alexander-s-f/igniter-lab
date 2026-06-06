

## Полный Delta: что можно реализовать прямо сейчас

### Категория 1: VM — Missing Opcodes (чисто технические, ноль governance)

**Текущий instruction set: 15 opcodes** (`0x01–0x0F` + `0x10–0x15`)

Что отсутствует при наличии всей грамматики в parser/typechecker:

| Опкод | Оператор | Где нужен |
|---|---|---|
| `OP_LT` `0x16` | `<` | Comparisons, invariants |
| `OP_LE` `0x17` | `<=` | Range checks, cardinality |
| `OP_GE` `0x18` | `>=` | Range checks |
| `OP_NE` `0x19` | `!=` | Status checks |
| `OP_AND` `0x1A` | `&&` | Compound invariants |
| `OP_OR` `0x1B` | `\|\|` | Alternative conditions |
| `OP_NOT` `0x1C` | `!` unary | Negation |
| `OP_CONCAT` `0x1D` | `++` | String/array join |
| `OP_PUSH_ARRAY` `0x1E` | `[a, b, c]` | Array literals |
| `OP_PUSH_RECORD` `0x1F` | `{k: v}` | Record construction |
| `OP_CALL` `0x20` | `fn(args)` | Named function calls |

Все эти операторы **парсятся и type-check'аются**, но `compiler.rs` падает с `"Unsupported binary operator"`. Это один файл, один ход работы.

---

### Категория 2: TBackend VM Binding — критический разрыв

`OP_LOAD_AS_OF` объявлен и в VM есть `trait TBackend` с двумя реализациями (`MemoryHistoryBackend`, `LedgerTcpBackend`). Но **они не соединены**:

```
OP_LOAD_AS_OF в vm.rs → только читает из inputs/temporal_context
                       → НЕ вызывает backend.read_as_of()

OP_EMIT_OBS в vm.rs   → только пишет в observation_sink Vec
                       → НЕ вызывает backend.append_observation()
```

`LedgerTcpBackend` полностью реализован с CRC32-framing, `latest_for`, ISO8601 parsing. `MemoryHistoryBackend` тоже работает. Нужно только **подключить** их к opcode handlers. Без этого все ESCAPE contracts — мёртвый код.

**Это разблокирует `AvailabilityProjection`, `TenantAvailabilityProjection`, и весь shadow experiment.**

---

### Категория 3: Compiler — Missing Expression Kinds

`compiler.rs::compile_expr()` не знает этих AST node kinds:

| Kind | Что нужно | Пример |
|---|---|---|
| `"lambda"` / `"fn"` | `OP_CALL` | `filter(leads, fn(x) { x.status == "active" })` |
| `"record"` | `OP_PUSH_RECORD` | `{ name: "x", value: 42 }` |
| `"array"` | `OP_PUSH_ARRAY` | `[1, 2, 3]` |
| `"let"` | `STORE_REG` + `LOAD_REG` | `let x = compute(...)` |
| `"unary"` | `OP_NOT` / `OP_NEG` | `!flag`, `-amount` |
| `"concat"` | `OP_CONCAT` | `first_name ++ " " ++ last_name` |

Все они генерируются emitter'ом из реальных `.ig` контрактов — просто компилятор не умеет их lowering'ить в bytecode.

---

### Категория 4: OOF-M1 — Modifier Enforcement

В `classifier.rs` уже есть `OOF-M1` (строка 935). Но модификаторы `pure`, `observed`, `privileged`, `irreversible` парсятся и **не проверяются** в runtime:

| Модификатор | Что должен делать | Статус |
|---|---|---|
| `pure` | OOF-M1 если контракт содержит ESCAPE ноды | ⚠️ частично |
| `observed` | только reads, no writes (ESCAPE ok) | ❌ нет проверки |
| `privileged` | требует capability token в manifest | ❌ нет |
| `irreversible` | требует отсутствие compensation | ❌ нет |

PROP-031 полностью принят (25/25 PASS). Это enforcement в classifier — один файл.

---

### Категория 5: igniter-machine — PROP-042 готов, реализации нет

PROP-042 написан полностью (`igniter-machine/PROP-042.md`). Директория `igniter-machine/` содержит только этот файл. Вся архитектура описана:
- `IgniterMachine` struct с `TBackend` trait
- `InMemoryBackend`, `RocksDBBackend`, `RemoteTcpBackend`
- `.igm` image format (MessagePack, 3 blocks)
- `checkpoint()` / `resume()` lifecycle
- Magnus FFI bindings для Ruby

**Это самый большой самостоятельный шаг** — создать `igniter-machine/` crate, объединить `igniter-tbackend` + `igniter-vm` + `igniter-compiler` в одном процессе без TCP.

---

### Категория 6: acts-as-tbackend — Hardening для Shadow

Уже работает как sketch. До более твердого shadow-hardening среза не хватает:

| Что | Почему нужно |
|---|---|
| Async write (Thread/Sidekiq) | CRM не должен ждать shadow |
| Silent failure rescue guard | Shadow crash ≠ CRM crash |
| Connection pool с timeout | Защита от зависшего TBackend |
| Circuit breaker (3 fails → skip) | Graceful degradation |
| ENV-based config | `SHADOW_HOST`, `SHADOW_PORT`, `SHADOW_ENABLED` |

Всё — Ruby, никакого governance.

---

### Категория 7: stdlib — Расширение

`igniter-stdlib` имеет `math.ig` (верифицирован) и минимальный `collections.ig`. Без дополнительного governance можно реализовать:

| Функция | Сигнатура | Приоритет |
|---|---|---|
| `count(coll)` | `Collection[T] → Integer` | 🔴 нужен для LeadConversionRate |
| `first(coll)` | `Collection[T] → Option[T]` | 🟠 |
| `last(coll)` | `Collection[T] → Option[T]` | 🟠 |
| `filter(coll, pred)` | `Collection[T], Fn → Collection[T]` | 🔴 нужен везде |
| `sum(coll, field)` | `Collection[T], Symbol → Decimal[S]` | 🔴 BidSummary |
| `zip(a, b)` | `Collection[A], Collection[B] → Collection[(A,B)]` | 🟡 |
| `range(from, to)` | `Integer, Integer → Collection[Integer]` | 🟡 |

---

### Категория 8: Conformance Test Suite — ICTS baseline

Сейчас `verify_compiler.rb` проверяет 6 fixtures. Нет:
- OOF fixture contracts (должны компилироваться с ошибками)
- Runtime execution fixtures (beyond loops_and_recursion)
- Cross-implementation comparison (Ruby canonical vs Rust lab)
- JSON Schema validation для `.igapp` format

Это **независимо** от всего — просто Ruby test files.

---

## Приоритетная карта

```
Разблокирует больше всего других вещей:

  🔴 P0 ─── TBackend binding в VM (OP_LOAD_AS_OF → backend)
             └── разблокирует: ESCAPE contracts, shadow experiment,
                 AvailabilityProjection, TenantAvailabilityProjection

  🔴 P0 ─── Missing opcodes: <, <=, !=, &&, ||, !
             └── разблокирует: все compound invariants, filter predicates,
                 VendorLeadPipeline conditions

  🟠 P1 ─── Compiler missing expression kinds (lambda, record, array, let)
             └── разблокирует: stdlib filter/map с lambdas, record outputs

  🟠 P1 ─── OOF-M1 modifier enforcement (pure, observed)
             └── разблокирует: PROP-031 полное доказательство

  🟠 P1 ─── acts-as-tbackend hardening (async, rescue, circuit breaker)
             └── разблокирует: shadow experiment start

  🟡 P2 ─── stdlib collections expansion (count, filter, sum)
             └── разблокирует: LeadConversionRate, BidSummary execution

  🟡 P2 ─── ICTS OOF fixture suite
             └── разблокирует: conformance evidence для canonical

  🟢 P3 ─── igniter-machine implementation (PROP-042)
             └── разблокирует: unified kernel, REPL, DX vision
```

**Итого без canonical**: 8 категорий, ~все реализуемы. Самое ценное по соотношению усилие/разблокировка — **TBackend binding в VM** (один файл, ~50 строк) и **missing opcodes** (один файл, ~30 строк). После них ESCAPE contracts начинают работать — и shadow experiment становится возможным.
