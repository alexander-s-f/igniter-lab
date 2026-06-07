
## Анализ: Что есть, чего нет, и что блокирует Rust реализацию

### Реальное состояние в igniter-lab Rust

**Хорошая новость:** `fold_stream` полностью реализован в трёх слоях — parser, classifier (OOF-S3/S4), typechecker. И в VM уже есть настоящий `fold`/`map`/`filter` внутри `OP_MAP_REDUCE` обработчика (vm.rs строки 318–394, включая `'item_loop` с аккумулятором). Это не заглушка — это работающий код.

**Плохая новость:** Это `fold_stream` — детерминированная редукция bounded stream. Вопрос из документа про другое: **произвольные управляемые циклы и рекурсия**.

### Delta-матрица: loops/recursion

| Концепт | Compiler (parser) | Classifier | TypeChecker | VM | Gap |
|---|---|---|---|---|---|
| `fold_stream` | ✅ | ✅ OOF-S3/S4 | ✅ | ✅ `MAP_REDUCE` | — |
| `stream` + `window` | ✅ | ✅ | ✅ | ❌ нет выполнения | VM только |
| `loop Name in coll max_steps: N` | ❌ | ❌ | ❌ | ❌ | Полный gap |
| `decreases fuel` (рекурсия) | ❌ | ❌ | ❌ | ❌ | Полный gap |
| `now()` запрет (OOF-M1/M2) | ❌ | ❌ | ❌ | — | Lexer/parser gap |
| `loop tick in clock.every(N)` | ❌ | ❌ | ❌ | ❌ | Полный gap |
| `service contract` modifier | ❌ | ❌ | ❌ | ❌ | Полный gap |
| `progression` fragment class | ❌ | ❌ | ❌ | — | Requires canonical |
| Loop naming enforcement (Постулат 28) | ❌ | ❌ | ❌ | — | Enforcement gap |
| `LOOP_START/STEP/END` opcodes | — | — | — | ❌ | VM gap |
| Fuel counter в VM | — | — | — | ❌ | VM gap |

---

### Что из Q1–Q4 требует canonical, а что нет

Это ключевой вопрос — что блокирует **реально**, а что можно двигать уже сейчас.

| Вопрос из документа | Требует canonical? | Почему |
|---|---|---|
| **Q1**: синтаксис `loop`/`for` + `max_steps` | ❌ — можно сделать draft | Синтаксис очевиден из Постулата 14, AST узел не требует governance |
| **Q1**: `decreases fuel` для рекурсии | ❌ — можно сделать draft | Техническая реализация, canonical нужен только для утверждения OOF кода |
| **Q2**: fragment class для progression | ✅ — нужен canonical | Это governance решение (CORE? ESCAPE? Новый класс?) |
| **Q2**: `service contract` → SemanticIR lowering | ⚠️ — черновик можно, spec нет | Можно реализовать как draft `service_loop_node`, без final semantics |
| **Q3**: запрет `now()` — OOF-M1/M2 | ❌ — можно сделать сейчас | Это однострочное изменение в lexer, canonical нужен только для OOF кода |
| **Q3**: `tick.time` как temporal binding | ❌ — можно сделать draft | Техническая реализация `LOAD_TICK` opcode |
| **Q4**: именование циклов (Постулат 28) | ❌ — enforcement в parser | Postulate 28 уже канон, enforcement — это implementation detail |

**Вывод: 3 из 4 вопросов igniter-lab может закрыть самостоятельно как draft → pressure.** Единственное что требует canonical решения — fragment class для progression.

---

## Что нужно сделать: Prioritized Close Plan

### 🔴 Tier 1 — Разблокировать сейчас (быстро, без canonical)

**T1.1: `now()` запрет в lexer — 1–2 часа**

```rust
// lexer.rs — при токенизации:
Token::Ident(name) if name == "now" => {
    errors.push(ParseErrorDetail {
        rule: "OOF-L-NOW".to_string(),
        severity: "error".to_string(),
        message: "now() is forbidden in contract bodies — use explicit as_of binding or tick.time".to_string(),
        token: "now".to_string(),
        line: self.line, col: self.col,
    });
}
```

Это самое быстрое закрытие из всех четырёх вопросов. И это правильно по Постулату 14 (управляемые циклы) + Постулату 1 (честность — нельзя прятать время в глобальном вызове).

---

**T1.2: `loop Name in expr max_steps: N { }` в parser — 1–2 дня**

```rust
// parser.rs — новый AST узел:
pub enum BodyDecl {
    // ... existing variants ...
    Loop {
        name: String,                    // Постулат 28: имя обязательно
        collection: Box<Expr>,           // источник итерации
        max_steps: Option<u64>,          // Постулат 14: конечность
        body: Vec<BodyDecl>,             // тело
    },
}

// Синтаксис:
// loop ProcessLeads in pending_leads max_steps: 1000 {
//   compute result = process_lead(lead)
//   emit result
// }
```

Classifier logic: если `collection` CORE → loop CORE; если ESCAPE (reads) → loop ESCAPE. Это не новый fragment class — просто propagation.

---

**T1.3: Loop naming enforcement (Постулат 28) — в parser, часть T1.2**

```rust
// При парсинге loop:
if name.is_empty() {
    self.errors.push(ParseErrorDetail {
        rule: "OOF-L-NAME".to_string(),
        message: "Loop must have an explicit name (Postulate 28)".to_string(),
        ..
    });
}
```

---

**T1.4: `LOOP_START` / `LOOP_STEP` / `LOOP_BREAK` в VM — 1 день**

```rust
// instructions.rs
pub const OP_LOOP_START: u8  = 0x12;  // args: [name: String, max_steps: Integer]
pub const OP_LOOP_STEP: u8   = 0x13;  // args: [] — проверяет fuel, JMP если исчерпан
pub const OP_LOOP_BREAK: u8  = 0x14;  // args: [] — принудительное завершение
pub const OP_LOAD_TICK: u8   = 0x15;  // args: [interval_ms: Integer] — clock tick binding

// vm.rs — fuel counter в execution context:
struct LoopFrame {
    name: String,
    fuel: u64,
    max_steps: u64,
}

// OP_LOOP_STEP: fuel -= 1; if fuel == 0 → OOF-L-FUEL error
```

Это не меняет семантику fold/map — это добавляет **явные управляемые циклы** как отдельный примитив поверх существующего `MAP_REDUCE`.

---

**T1.5: `decreases fuel` для рекурсии — 1–2 дня**

```rust
// В функциях (def):
pub struct FunctionDecl {
    pub name: String,
    pub params: Vec<(String, TypeAnnotation)>,
    pub return_type: TypeAnnotation,
    pub decreases: Option<String>,  // "decreases fuel" — доказательство конечности
    pub body: ExprOrBlock,
}

// TypeChecker: если функция рекурсивна (вызывает себя)
// и нет decreases → OOF-L-RECURSE
```

---

### 🟠 Tier 2 — Draft без canonical (средний горизонт)

**T2.1: `loop tick in clock.every(N.seconds) { as_of = tick.time }` — 2–3 дня**

```rust
// parser.rs — service loop variant:
pub enum BodyDecl {
    ServiceLoop {
        name: String,
        interval: ClockInterval,    // clock.every(5.seconds)
        body: Vec<BodyDecl>,
    },
}

// Clock interval в AST:
pub struct ClockInterval {
    pub value: u64,
    pub unit: String,   // "seconds", "minutes", "hours"
}

// Emitter: → service_loop_node в SemanticIR
// VM: LOAD_TICK opcode + tick.time как detached temporal binding
```

Это draft — semantics будут уточнены canonical когда придёт PROP-037+. Но синтаксис и AST уже зафиксированы как pressure.

---

**T2.2: `service_loop_node` в SemanticIR emitter — 1 день**

```json
{
  "kind": "service_loop_node",
  "name": "ProcessLeadQueue",
  "interval": { "value": 60, "unit": "seconds" },
  "fragment": "escape",       // service loops всегда ESCAPE (side effects)
  "temporal_binding": "tick.time",
  "body_nodes": [ ... ]
}
```

Это даёт canonical конкретный IR для обсуждения fragment class вопроса из Q2.

---

### 🟡 Tier 3 — Requires canonical (ждём решения)

**T3.1: Fragment class для `progression`**

Это единственное что **реально требует** canonical governance decision. Вопрос Q2 из документа:

> Получает ли прогрессия выделенный fragment class или остаётся escape с метаданными?

Три варианта для canonical:

| Вариант | Fragment Class | Последствия |
|---|---|---|
| A | `escape` + `service_loop` metadata в manifest | Проще, меньше изменений |
| B | Новый class `temporal_loop` | Богаче, требует classifier расширения |
| C | `progression` как отдельный класс (как `epistemic`) | Максимально явно, сложнее |

igniter-lab может реализовать вариант A сейчас как draft, переключиться на B или C когда canonical решит.

---

**T3.2: Официальные OOF коды для loops**

Сейчас igniter-lab использует неформальные коды (`OOF-L-NOW`, `OOF-L-NAME`, `OOF-L-RECURSE`). Нужна canonical регистрация. Предложение для PROP-037+:

| Код | Нарушение |
|---|---|
| `OOF-L1` | Unbounded loop (нет `max_steps`) |
| `OOF-L2` | `now()` в теле контракта |
| `OOF-L3` | Безымянный loop (Постулат 28) |
| `OOF-L4` | Рекурсия без `decreases fuel` |
| `OOF-L5` | Loop accumulator содержит ESCAPE ref |
| `OOF-SL1` | Service loop без `clock` binding |
| `OOF-SL2` | Service loop в CORE contract |

---

## Итоговый Close Plan

```
Tier 1 — Без canonical, быстро:
  T1.1  now() ban в lexer              ~2 часа   ← сделать первым
  T1.2  loop AST + parser              ~2 дня
  T1.3  loop naming enforcement        ~0 (часть T1.2)
  T1.4  LOOP_START/STEP/BREAK в VM     ~1 день
  T1.5  decreases fuel в parser+TC     ~2 дня

  Итого Tier 1: ~5–6 дней → разблокирует Rust реализацию на 80%

Tier 2 — Draft без canonical:
  T2.1  service loop syntax + clock.every  ~3 дня
  T2.2  service_loop_node в emitter        ~1 день

  Итого Tier 2: ~4 дня → даёт canonical конкретный IR для Q2 decision

Tier 3 — Ждём canonical:
  T3.1  progression fragment class         Governance decision
  T3.2  OOF-L* registry                   PROP-037+ ratification

  Но Tier 3 НЕ блокирует Tier 1 и Tier 2!
```

**Главный вывод**: документ правильно направлен как pressure package, но неверно обозначает blocked status. **igniter-lab может двигаться на 80% без ответа canonical** — реализовать T1 и T2, отправить как concrete pressure с работающим кодом и SemanticIR примерами. Это намного сильнее чем вопросы без кода — canonical получит рабочий draft для review, а не абстрактные Q.
