---

# igniter-lab Shadow Production Report
## Теневой эксперимент рядом со Spark CRM

---

## I. Тезис эксперимента

**Shadow production** — это режим, при котором igniter-lab получает те же данные что и Spark CRM, выполняет те же бизнес-вычисления через igniter contracts, и сравнивает результаты — не влияя на production ни байтом.

Это доказывает три вещи которые нельзя доказать в лаборатории:

1. **Semantic correctness** — igniter contracts воспроизводят реальную бизнес-логику Spark CRM точно
2. **Temporal superiority** — igniter даёт аудит и time-travel который CRM не умеет
3. **Production viability** — igniter выдерживает реальный поток данных с реальными edge cases

Важный контекст: **доменные контракты уже существуют как fixtures**. `vendor_lead_pipeline.ig`, `availability_projection.ig`, `tenant_availability_projection.ig`, `decimal_contract.ig` (BidSummary) — это не абстрактные примеры. Это спецификации Spark CRM domain, написанные через applied pressure experiments в canonical igniter-lang. Shadow experiment — это их первое исполнение на реальных данных.

---

## II. Shadow Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SPARK CRM (Production)                    │
│                                                             │
│  Vendor   Lead   Opportunity   Bid   Availability   Technician │
│     │       │         │         │         │              │   │
│     └───────┴─────────┴─────────┴─────────┴──────────────┘   │
│                         │                                    │
│              after_commit (async, fire-and-forget)           │
│              acts_as_tbackend hook                           │
└────────────────────────────┬────────────────────────────────┘
                             │ TCP (port 7401)
                             │ non-blocking, CRM не ждёт ответа
                             ▼
┌─────────────────────────────────────────────────────────────┐
│                igniter-tbackend (Shadow Store)               │
│                                                             │
│  Store: vendors    Store: leads    Store: bids              │
│  Store: availability  Store: technicians  Store: opportunities │
│                                                             │
│  WAL (дурабельность)   128-shard RwLock (concurrency)       │
│  BLAKE3 content hash   CRC32 wire framing                   │
│                                                             │
│  PipelinePack: reactive triggers на новые факты             │
│  TriggerPack: webhook → contract executor                   │
└──────────────────┬──────────────────────────────────────────┘
                   │ реактивный триггер на write_fact
                   ▼
┌─────────────────────────────────────────────────────────────┐
│              Contract Executor (igniter-vm)                  │
│                                                             │
│  VendorLeadPipeline.igapp   → shadow result                 │
│  AvailabilityProjection.igapp → shadow result               │
│  BidSummary.igapp           → shadow result                 │
│  TenantAvailability.igapp   → shadow result                 │
│                                                             │
│  inputs: из igniter-tbackend (latest_for / as_of)          │
│  observations: EMIT_OBS → observation sink                  │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                Shadow Comparison Store                       │
│                                                             │
│  { contract, crm_result, igniter_result, delta, latency }  │
│  Accumulates evidence over time                             │
└──────────────────┬──────────────────────────────────────────┘
                   │
                   ▼
┌─────────────────────────────────────────────────────────────┐
│                Evidence Dashboard                            │
│  Accuracy %, Temporal coverage, Latency, OOF rate           │
└─────────────────────────────────────────────────────────────┘
```

### Ключевой принцип: CRM никогда не ждёт igniter

```ruby
# acts_as_tbackend — async, fire and forget
after_commit :commit_to_shadow, on: %i[create update destroy]

def commit_to_shadow
  Thread.new do  # или Sidekiq job — CRM не блокируется
    ActsAsTbackend.client.write_fact(
      store: self.class.table_name,
      key: id.to_s,
      value: shadow_attributes,
      valid_time: @shadow_valid_time
    )
  rescue => e
    ShadowMonitor.log_failure(e)  # silent failure — production не затронут
  end
end
```

---

## III. Delta: igniter-lab vs Shadow Production Requirements

### 3.1 Data Capture Layer

| Требование | igniter-lab сейчас | Gap | Приоритет |
|---|---|---|---|
| AR `after_commit` → TBackend | ✅ `acts-as-tbackend` sketch | Нужен hardening + async | 🔴 P0 |
| Fire-and-forget (CRM не блокируется) | ⚠️ Sync TCP сейчас | Нужен async/Thread | 🔴 P0 |
| Silent failure mode (shadow crash ≠ CRM crash) | ❌ Нет | Нужен rescue guard | 🔴 P0 |
| `valid_time` backdating через AR | ✅ `attr_accessor :valid_time` | Есть | ✅ |
| Схема фильтрации (only: / except: для полей) | ✅ В opts | Есть | ✅ |
| Multi-model capture (6 моделей Spark) | ✅ Паттерн есть | Нужна конфигурация | 🟠 P1 |
| Connection pool (thread-local client) | ✅ Thread.current cache | Есть | ✅ |
| WAL durability на стороне tbackend | ✅ FileBackend | Есть | ✅ |

### 3.2 Shadow Store (igniter-tbackend)

| Требование | igniter-lab сейчас | Gap | Приоритет |
|---|---|---|---|
| 128-shard concurrent writes | ✅ ShardedFactLog | Есть | ✅ |
| O(log N) temporal lookup | ✅ `partition_point` | Есть | ✅ |
| `latest_for(store, key, as_of:)` | ✅ CorePack | Есть | ✅ |
| `facts_for(store, key, since:, as_of:)` | ✅ CorePack | Есть | ✅ |
| `query_scope` с pushdown filters | ✅ QueryPack | Есть | ✅ |
| Cross-store temporal join | ✅ CrossStorePack | Есть | ✅ |
| Реактивный trigger на write_fact | ✅ PipelinePack | Нужна конфигурация | 🟠 P1 |
| Webhook dispatch к executor | ✅ TriggerPack | Нужна конфигурация | 🟠 P1 |
| Auth для shadow endpoint | ✅ AuthPack | Нужна конфигурация | 🟠 P1 |
| P2P gossip (multi-node shadow) | ✅ MeshClusterPack | Phase 3+ | 🟢 P3 |
| Compaction (долгий WAL) | ✅ SnapshotPack | Phase 3+ | 🟢 P3 |

### 3.3 Contract Compiler

| Требование | igniter-lab сейчас | Gap | Приоритет |
|---|---|---|---|
| `vendor_lead_pipeline.ig` → .igapp | ✅ Компилируется | .igapp в out/ | ✅ |
| `availability_projection.ig` → .igapp | ✅ Компилируется | .igapp в out/ | ✅ |
| `decimal_contract.ig` (BidSummary) → .igapp | ✅ Компилируется | .igapp в out/ | ✅ |
| `tenant_availability_projection.ig` → .igapp | ✅ Компилируется | .igapp в out/ | ✅ |
| Hot-reload .igapp без restart | ❌ Нет | Нужен Resident Supervisor | 🟠 P2 |
| Contract version management | ❌ Нет | Нужна схема | 🟠 P2 |
| Compilation error ≠ shadow failure | ❌ Нет | Нужен guard | 🟠 P1 |

### 3.4 Contract Executor (igniter-vm)

| Требование | igniter-lab сейчас | Gap | Приоритет |
|---|---|---|---|
| Execute CORE contracts (arithmetic, logic) | ✅ 25 opcodes | Есть | ✅ |
| Execute ESCAPE contracts (TBackend reads) | ⚠️ Есть `tbackend.rs` stub | Нужна binding к igniter-tbackend | 🔴 P0 |
| `LOAD_AS_OF` temporal context | ✅ opcode | Есть | ✅ |
| `EMIT_OBS` observation sink | ✅ opcode | Есть | ✅ |
| if/else branching (VendorLead pipeline steps) | ✅ JMP_IF / JMP_UNLESS | Есть | ✅ |
| Decimal arithmetic (BidSummary) | ✅ через igniter-stdlib | Есть | ✅ |
| `fold_stream` / `window` execution | ❌ Нет в VM | Нужна реализация | 🟠 P2 |
| Collection operations (map, filter, fold) | ⚠️ MAP_REDUCE opcode заглушка | Нужна реализация | 🟠 P1 |
| Multi-contract pipeline (step sequencing) | ❌ Нет | Нужен orchestrator | 🟠 P2 |

### 3.5 Comparison & Measurement

| Требование | igniter-lab сейчас | Gap | Приоритет |
|---|---|---|---|
| CRM result capture (что сравнивать) | ❌ Нет | Нужна shadow result store | 🔴 P0 |
| Delta computation (igniter vs CRM) | ❌ Нет | Нужна comparison logic | 🔴 P0 |
| Accuracy metrics | ❌ Нет | Нужен metrics collector | 🟠 P1 |
| Latency tracking | ❌ Нет | Нужен timing wrapper | 🟠 P1 |
| Evidence dashboard | ⚠️ `todolist/ui.rb` паттерн | Нужен shadow dashboard | 🟠 P2 |
| Temporal reconstruction proof | ❌ Нет | Phase 2 | 🟠 P2 |
| OOF rate monitoring | ❌ Нет | Phase 2 | 🟡 P3 |

---

## IV. Spark CRM Domain — Контракты для Shadow

### Контракт 1: VendorLeadPipeline (уже есть fixture)

```igniter
module SparkCRM.Marketing

pipeline VendorLeadIntake {
  step validate_and_find_vendor
  step check_business_hours
  step query_geo_bids
  step build_response
}
```

**Что доказывает в shadow**: Igniter может воспроизвести полный vendor intake flow — от входящего лида до bid response — с тем же результатом что Spark CRM, но с полным битемпоральным аудитом каждого шага.

**CRM result**: итоговый bid response из Spark CRM DB
**Shadow result**: observations из VM execution
**Delta**: совпадают ли шаги, bid amount, vendor selection

---

### Контракт 2: AvailabilityProjection (уже есть fixture)

```igniter
contract AvailabilityProjection {
  read geo_signals: Collection[GeoSignal] from TBackend lifecycle: :window
  read schedule: ScheduleFact from TBackend lifecycle: :durable

  window "availability_window" { unit: :calendar, frame: :day }

  compute slots = compute_availability(geo_signals, schedule)
  snapshot daily_snapshot = build_snapshot(slots, ...) lifecycle: :durable

  output snapshot: AvailabilitySnapshot
}
```

**Что доказывает**: Igniter воспроизводит availability calculation из реальных Spark CRM geo signals и schedule данных. Битемпоральный snapshot позволяет запросить «что была availability 3 недели назад» — чего CRM не умеет.

**Уникальная ценность shadow**: temporal reconstruction недоступная в Spark CRM

---

### Контракт 3: BidSummary / Decimal precision (уже есть fixture)

```igniter
contract BidSummary {
  input bids: Collection[BidFact]

  compute total_net    = sum_decimal(bids, :net_amount)    -- Decimal[2]
  compute total_tax    = sum_decimal(bids, :tax_amount)    -- Decimal[4]
  compute grand_total  = add(total_net, convert_scale(total_tax, 2))

  output summary: BidSummaryResult  -- Decimal[2]
}
```

**Что доказывает**: Igniter правильно обрабатывает финансовую арифметику с фиксированной точкой. Decimal[2] для invoice totals совпадает с тем что считает Spark CRM. Это критичный тест — если igniter ошибается в копейках, это видно сразу.

**Precision test**: scale tracking гарантирует OOF-TC5 при scale mismatch

---

### Контракт 4: TenantAvailabilityProjection (уже есть fixture)

```igniter
contract TenantAvailabilityProjection {
  input tenant_id: String
  input vendor_id: String

  read slots: Collection[TimeSlot]
    from TBackend
    scoped_by tenant: tenant_id
    cardinality 1..500
    schema_version 2
    lifecycle: :window

  output projection: TenantProjection
}
```

**Что доказывает**: Multi-tenant isolation работает корректно. scoped_by + cardinality — это реальные Spark CRM constraints.

---

### Новые контракты для shadow (не существуют в fixtures)

| Контракт | Бизнес-смысл | Сложность | Фаза |
|---|---|---|---|
| LeadConversionRate | % лидов → opportunities за период | ESCAPE + temporal | P2 |
| VendorRankingProjection | Ranking по bid win rate | ESCAPE + analytics | P2 |
| RevenueProjection | Доход forecast с as_of | temporal + Decimal | P2 |
| ChurnRiskSignal | Vendor churn по activity patterns | epistemic + stream | P3 |
| BidCompetitivenessIndex | OLAPPoint по geo × category × time | OLAP | P3 |

---

## V. Measurement Framework: Что Доказываем

### Метрика 1: Shadow Accuracy Rate

```
accuracy = (matching_results / total_shadow_executions) × 100%

Цель Phase 1: ≥ 80% (baseline)
Цель Phase 2: ≥ 95% (production confidence)
Цель Phase 3: ≥ 99% (certification evidence)
```

Расхождение — это сигнал: либо igniter contract неточно выражает CRM логику, либо CRM имеет баг, либо данные пришли с задержкой (temporal gap).

### Метрика 2: Temporal Reconstruction Accuracy

```
reconstruction_accuracy = (correct_historical_states / sampled_queries) × 100%

Запрос: "Что была availability vendor X в дату Y?"
Igniter отвечает via as_of: temporal query
CRM: не может (нет bitemporal audit)
```

Это метрика **уникального преимущества** igniter — CRM не может её сравнить, только подтвердить через ручную проверку.

### Метрика 3: Shadow Latency

```
shadow_latency = tbackend_write_time + reactive_trigger_time + vm_execution_time

Цель: < 200ms для simple contracts (Add, BidSummary)
Цель: < 1s для complex contracts (AvailabilityProjection)

CRM не ждёт — это фоновая метрика для evidence только
```

### Метрика 4: Coverage

```
coverage = (shadowed_operations / total_crm_operations) × 100%

Phase 1: ключевые модели (Vendor, Lead, Bid)
Phase 2: все основные модели
Phase 3: полное покрытие
```

### Метрика 5: OOF Detection Rate

```
oof_rate = (oof_executions / total_executions) × 100%

Это неожиданно ценная метрика: OOF = data quality violation
Если igniter видит OOF — это сигнал о реальной проблеме в CRM данных
```

---

## VI. Roadmap: 4 Фазы

### Phase 0 — Shadow Infrastructure (3–4 недели)
*Цель: Shadow store работает, данные текут, CRM не затронут*

**P0.1: acts-as-tbackend Hardening**
```ruby
# Что нужно добавить:

# 1. Async wrapper — CRM не блокируется
def commit_to_shadow
  ShadowWorker.perform_async(
    store: self.class.table_name,
    key: id.to_s,
    value: shadow_attributes
  )
end

# 2. Silent failure guard
rescue ShadowConnectionError, Timeout::Error => e
  ShadowMonitor.record_failure(self.class.name, id, e)
  # Production продолжает нормально

# 3. Configurable field filter
acts_as_tbackend(
  only: %i[id name status amount vendor_id created_at],
  host: ENV["SHADOW_TBACKEND_HOST"],
  port: ENV["SHADOW_TBACKEND_PORT"].to_i
)
```

**P0.2: igniter-tbackend Shadow Service**
- Deploy как отдельный процесс (не на production сервере)
- Config: `host: shadow.internal, port: 7401, data_dir: /data/shadow`
- Включить: CorePack, BaseAuditPack, QueryPack, AuthPack
- WAL на persistent volume

**P0.3: Spark CRM Models → Shadow**
```ruby
# В каждой AR модели (или base concern):
class Vendor < ApplicationRecord
  acts_as_tbackend only: %i[id name status region tier created_at updated_at]
end

class Lead < ApplicationRecord
  acts_as_tbackend only: %i[id vendor_id status source geo_zone bid_amount created_at]
end

class Bid < ApplicationRecord
  acts_as_tbackend only: %i[id lead_id vendor_id net_amount tax_amount status valid_time]
end
```

**P0.4: Shadow Result Store**
```ruby
# Отдельная таблица или Redis — не в CRM DB
class ShadowResult
  # contract_name, inputs_hash, crm_result, igniter_result,
  # matched, delta_json, latency_ms, executed_at
end
```

**P0.5: ESCAPE contract TBackend binding в igniter-vm**
- Сейчас `tbackend.rs` в igniter-vm — заглушка
- Реализовать: `LOAD_REF` для `read from TBackend` → TCP call к igniter-tbackend
- Это критический gap: без него ESCAPE contracts не работают

**Deliverables Phase 0:**
- Shadow store принимает данные от Spark CRM
- 3 AR модели настроены (Vendor, Lead, Bid)
- ESCAPE contract TBackend binding работает
- `ping` + `write_fact` + `latest_for` verified

---

### Phase 1 — First Shadow Contract (4–5 недель)
*Цель: BidSummary и VendorLeadPipeline в тени, первые accuracy метрики*

**P1.1: BidSummary как первый shadow contract**
- Самый простой: CORE + Decimal, нет TBackend reads
- Compile `decimal_contract.ig` → `.igapp`
- Execute через igniter-vm на shadow bid data
- Compare с Spark CRM invoice totals
- Decimal precision — критичный первый тест

**Почему BidSummary первым**: Нет зависимости от ESCAPE/TBackend, чистая арифметика. Если igniter считает Decimal неправильно — это видно немедленно, до любой сложности.

**P1.2: CRM Result Capture Hook**
```ruby
# В Spark CRM — рядом с бизнес-логикой:
class BidService
  def calculate_summary(bids)
    result = # ... existing CRM logic
    ShadowComparison.submit_crm_result(
      contract: "BidSummary",
      inputs: { bid_ids: bids.map(&:id) },
      result: result
    )
    result
  end
end

# Async: shadow executor подхватывает те же inputs,
# вычисляет через igniter-vm, сравнивает
```

**P1.3: Map/Filter/Fold в igniter-vm**
- MAP_REDUCE opcode сейчас заглушка
- BidSummary требует `sum_decimal(bids, :net_amount)` → fold над collection
- Реализовать Collection operations: `count`, `filter`, `map`, `fold`, `first`

**P1.4: VendorLeadPipeline shadow**
- Сложнее: pipeline steps, условная логика
- Требует if/else (уже есть JMP_IF) + multi-step sequencing
- Реализовать simple pipeline orchestrator: выполнить steps последовательно

**P1.5: First Accuracy Report**
- После 1 недели shadow данных: первый отчёт
- Формат: `{ accuracy_rate, total_executions, matches, mismatches, top_deltas }`
- Расхождения → анализ: contract gap? data gap? timing gap?

**Deliverables Phase 1:**
- BidSummary: accuracy ≥ 80%, Decimal precision confirmed
- VendorLeadPipeline: first shadow results
- Collection operations в VM
- First accuracy report

---

### Phase 2 — Full Contract Portfolio (5–7 недель)
*Цель: все 4 fixture contracts в тени, temporal reconstruction proof*

**P2.1: AvailabilityProjection shadow**
- ESCAPE contract: требует `read from TBackend`
- TBackend reads: `geo_signals` (store: "geo_signals"), `schedule` (store: "schedules")
- Window lifecycle: `:day` window aggregation
- `compute_availability` stdlib function → igniter-stdlib FFI

**P2.2: TenantAvailabilityProjection shadow**
- Multi-tenant: `scoped_by tenant: tenant_id`
- QueryPack с tenant filter
- Cardinality validation (1..500)

**P2.3: Temporal Reconstruction Proof**
- Выбрать 10 случайных дат в прошлом (за период работы shadow)
- Запросить через igniter-tbackend: `latest_for(store, key, as_of: past_date)`
- Сравнить с historical CRM data (если есть) или с ручной проверкой
- Это доказывает: bitemporal audit работает в production conditions

**P2.4: Resident Supervisor**
- Без hot-reload: каждый запрос → load .igapp → compile → execute → overhead
- Resident Supervisor: держит .igapp in-memory, принимает dispatch requests
- Pattern из igniter-runtime proof → hardened implementation
- Formalize: `boot(igapp_dir)`, `dispatch(contract_name, inputs)`, `observe`

**P2.5: Evidence Dashboard (temporal REPL стиль)**
- Расширить `todolist/ui.rb` паттерн для shadow evidence
- Real-time: accuracy rate, latency histogram, coverage %, recent mismatches
- Time-travel view: точность по времени (улучшалась ли accuracy?)

**P2.6: PipelinePack Reactive Trigger**
- Сейчас: batch execution (cron или manual)
- Phase 2: reactive — `write_fact` → PipelinePack → contract executor
- Real-time shadow вместо batch shadow

**Deliverables Phase 2:**
- Все 4 fixture contracts в shadow
- Temporal reconstruction: 10/10 historical queries verified
- Resident Supervisor operational
- Reactive pipeline (real-time shadow)
- Accuracy: ≥ 95% на BidSummary, ≥ 90% на pipeline contracts

---

### Phase 3 — Production Evidence (6–8 недель)
*Цель: Level 3 certification evidence, новые contracts, production patterns*

**P3.1: LeadConversionRate contract**
```igniter
contract LeadConversionRate {
  input vendor_id: String
  input period_start: DateTime
  input period_end: DateTime

  read leads: Collection[LeadFact]
    from TBackend
    scoped_by vendor: vendor_id
    lifecycle: :window

  compute total_leads       = count(leads)
  compute converted         = count(filter(leads, :status, "converted"))
  compute conversion_rate   = div(converted, total_leads)

  invariant has_leads predicate: total_leads_positive severity: :warn

  output rate: ConversionResult
    evidence [conversion_rate, total_leads, converted]
}
```

**P3.2: Benchmark Suite vs Spark CRM**
- Сравнить latency: Spark CRM SQL query vs igniter contract execution
- Сравнить throughput: N contracts/second vs N CRM queries/second
- Temporal query latency: igniter O(log N) vs CRM full-table-scan with timestamps
- Это производительность как доказательство (не просто correctness)

**P3.3: OOF as Business Signal**
- OOF-rate monitoring: какие contracts регулярно попадают в OOF?
- Каждый OOF — это data quality violation или contract gap
- Создать OOF alert: если `availability_projection` видит OOF → это реальная проблема в расписании

**P3.4: igniter-chronicle gem**
- Официально оформить acts-as-tbackend как `igniter-chronicle`
- Full causation chain: каждый факт знает predecessor
- Audit API: `Model.chronicle_history(id)`, `Model.chronicle_at(id, as_of: t)`
- Это standalone value prop: любое Rails app получает bitemporal audit

**P3.5: MCP Tool для Spark CRM analytics**
- McpPack → MCP server на igniter-tbackend
- Tool: `query_vendor_history(vendor_id, as_of:)` → temporal facts
- Tool: `compute_bid_summary(vendor_id, period:)` → igniter contract result
- LLM agent может использовать Spark CRM data temporally через MCP

**Deliverables Phase 3:**
- 6+ contracts в shadow (4 fixture + 2 new)
- Benchmark report: igniter vs CRM
- OOF monitoring operational
- igniter-chronicle gem concept
- MCP tool interface для Spark data

---

### Phase 4 — Certification Evidence (ongoing)
*Цель: накопление доказательств достаточных для formal certification*

**P4.1: Shadow Report v1.0**
- Формальный отчёт: methodology, results, accuracy metrics, temporal proofs
- Этот документ → External Pressure Reviewer → Meta Expert → canonical PROP input
- Это первое production evidence для igniter-lang spec

**P4.2: ICTS Production Fixtures**
- Из shadow data генерировать golden fixtures для ICTS
- Реальные Spark CRM contracts → anonymized ICTS test cases
- Это обогащает conformance test suite реальными edge cases

**P4.3: Path to Production**
- Если accuracy ≥ 99% и latency приемлема → discuss возможность selective promotion
- Например: BidSummary computation → igniter-vm в production (не shadow)
- Это переход от shadow к альтернативной production реализации отдельного компонента

---

## VII. Технические Приоритеты (Backlog)

### Critical Path (нельзя не сделать)

| # | Задача | Компонент | Блокирует |
|---|---|---|---|
| C1 | Async shadow write (fire-and-forget) | acts-as-tbackend | Всё |
| C2 | Silent failure guard | acts-as-tbackend | CRM safety |
| C3 | ESCAPE TBackend binding в VM | igniter-vm/tbackend.rs | ESCAPE contracts |
| C4 | Collection ops (fold, filter, map) | igniter-vm | BidSummary |
| C5 | Shadow Result Store | новый | Measurement |
| C6 | CRM Result Capture hook | Spark CRM | Delta comparison |

### High Priority

| # | Задача | Компонент | Фаза |
|---|---|---|---|
| H1 | PipelinePack reactive trigger config | igniter-tbackend | P1 |
| H2 | Pipeline step sequencer | igniter-vm | P1 |
| H3 | Resident Supervisor | igniter-runtime | P2 |
| H4 | Temporal reconstruction test | igniter-tbackend | P2 |
| H5 | Window/fold_stream в VM | igniter-vm | P2 |
| H6 | Accuracy reporting | нет | P1 |

### Medium Priority

| # | Задача | Компонент | Фаза |
|---|---|---|---|
| M1 | Evidence dashboard | igniter-apps | P2 |
| M2 | OOF monitoring | нет | P2 |
| M3 | AuthPack конфигурация | igniter-tbackend | P1 |
| M4 | Contract hot-reload | Resident Supervisor | P2 |
| M5 | igniter-chronicle gem | acts-as-tbackend | P3 |
| M6 | McpPack formal schema | igniter-tbackend | P3 |

---

## VIII. Риски и Митигация

| Риск | Вероятность | Влияние | Митигация |
|---|---|---|---|
| Shadow write тормозит CRM | Средняя | Высокое | Async + timeout + circuit breaker |
| Shadow crash = CRM crash | Средняя | Критично | `rescue` guard, отдельный thread/process |
| Accuracy < 80% на старте | Высокая | Низкое | Ожидаемо — это discovery process |
| Temporal lag (CRM пишет быстрее shadow) | Средняя | Средняя | valid_time = CRM timestamp (backdating) |
| Data privacy (CRM data в shadow) | Высокая | Высокое | Same security perimeter, field filtering |
| VM performance insufficient | Средняя | Средняя | Resident Supervisor + Rust VM преимущество |
| Schema drift (CRM model changes) | Средняя | Средняя | schema_version в каждом факте |
| igniter-tbackend disk usage | Низкая | Средняя | SnapshotPack compaction Phase 3 |

---

## IX. Главный тезис Shadow Experiment

Spark CRM — это production system с годами бизнес-логики. Запустить igniter-lab рядом и получить accuracy ≥ 95% на тех же вычислениях — это не просто технический факт.

Это доказательство что:

1. **Igniter language достаточно выразителен** чтобы описать реальную бизнес-логику
2. **Bitemporal model превосходит** traditional CRM audit по temporal query capability
3. **Rust-native stack конкурентоспособен** по latency с production Rails/SQL
4. **Contract-as-spec работает**: те же `.ig` fixtures что писались как applied pressure — работают на реальных данных

И когда shadow accuracy достигает 99% — это момент когда igniter перестаёт быть экспериментом и становится альтернативой.
---