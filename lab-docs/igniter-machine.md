Это очень глубокая идея. Давай разберём оба варианта честно, потом поговорим о Machine.

---

## Сетевое связывание (текущий подход)

**Что есть сейчас:**
```
igniter-vm → TCP → igniter-tbackend
              JSON + CRC32 framing
              ~0.5–5ms per call
```

**Когда это правильно:**
- Shadow production (isolation — главное требование)
- Polyglot clients (Ruby, Python, Go пишут факты)
- Distributed deployment (VM на одном узле, TBackend на другом)
- Fault isolation (TBackend crash ≠ VM crash)

**Цена:**
- Каждый `read from TBackend` внутри contract = network round-trip
- `AvailabilityProjection` может делать 3–5 reads → 3–5 TCP calls
- Serialization: Value → JSON → bytes → parse → Value обратно
- Connection management overhead

Для shadow это приемлемо. Для embedded или development — нет.

---

## Machine: Unified Native System

Идея правильная и глубокая. Smalltalk Machine и R — точные референсы.

**Что объединяет эти системы:**

Smalltalk-80: Object Memory (heap) + Interpreter + Image (snapshot) + Environment — **неразделимы**. Нет "базы данных" и "рантайма" — есть единый живой граф объектов.

R: Workspace (все переменные, функции, данные) + Interpreter + `save.image()` / `load()` — единое пространство вычисления.

**Для Igniter это значит:**

```
Fact Memory (TBackend) + Contract Executor (VM) +
Compiler (in-process) + Image (checkpoint/resume)
= единый живой процесс
```

Никакого TCP. `read from TBackend` → прямой вызов `ShardedFactLog::latest_for()` в памяти. Sub-microsecond вместо milliseconds.

---

## Архитектурный эскиз

```rust
pub struct IgniterMachine {
    // Fact Memory — был отдельным сервисом
    facts: Arc<ShardedFactLog>,
    wal:   Arc<FileBackend>,       // дурабельность

    // Contract Registry — compiled contracts in-memory
    contracts: HashMap<String, CompiledContract>,  // .igapp загружены

    // Compiler — on-demand, без внешнего процесса
    compiler: Compiler,            // .ig → bytecode in-process

    // Executor
    vm: VM,

    // Observation Sink
    observations: Arc<Mutex<ObservationLog>>,

    // Extension Packs (тот же Packet Profile pattern)
    packs: PackRegistry,
}

impl IgniterMachine {
    // Smalltalk: fileIn/fileOut
    pub fn load_contract(&mut self, source: &str)          // compile + register
    pub fn dispatch(&self, name: &str, inputs: Inputs)     // execute

    // R: workspace facts
    pub fn write(&self, store: &str, key: &str, value: V)  // assert fact
    pub fn query(&self, store: &str, key: &str, as_of: T)  // temporal read

    // Smalltalk: image save/restore
    pub fn checkpoint(&self, path: &str)   // serialize entire machine state
    pub fn resume(path: &str) -> Self      // restore from image

    // Network bridge (опционально)
    pub fn serve(&self, addr: &str)        // expose as TCP server если нужно
}
```

---

## Нейминг

`igniter-machine` — честный, прямой, ref на Smalltalk Machine и PROP-006 (`RuntimeMachine`). Но немного generic.

Несколько вариантов с разными акцентами:

| Название | Акцент | Ощущение |
|---|---|---|
| `igniter-machine` | Computational machine | Честный, точный |
| `igniter-kernel` | Unified core | Системный, низкоуровневый |
| `igniter-world` | Smalltalk World / living system | Поэтичный, Alan Kay |
| `igniter-cell` | Биологическая клетка — самодостаточная единица | Компактный, органичный |
| `igniter-node` | Erlang node — self-contained compute unit | Распределённый акцент |
| `ignis` | Latin для fire, compact | Опаковый, требует контекста |
| `igniter-live` | Live system, Smalltalk Live | DX акцент |

**Мой фаворит: `igniter-kernel`**

Потому что:
- Kernel = ядро операционной системы — управляет памятью (facts), выполнением (VM), I/O (packs)
- Без сетевых расходов — это буквально kernel-mode vs user-mode аналогия
- Хорошо масштабируется: `igniter-kernel` внутри процесса, `igniter-server` снаружи
- REPL и IDE — это userland поверх kernel

Но `igniter-machine` тоже очень хорош если хочется прямой отсылки к language machine традиции.

---

## DX Vision: The Full Stack

Если принять Machine как отправную точку, естественно вырастает:

```
┌─────────────────────────────────────────────────┐
│                  igniter-ide                     │
│  (web UI: contract browser, temporal explorer,  │
│   observation inspector, fact timeline)          │
│  Arbre + Tailwind — igniter-frontend path        │
└──────────────────────┬──────────────────────────┘
                       │
┌──────────────────────▼──────────────────────────┐
│                 igniter-repl                     │
│  (interactive shell — как R console)            │
│                                                 │
│  >> load "vendor_lead_pipeline.ig"              │
│  => Compiled: VendorLeadPipeline (core)         │
│  >> dispatch :VendorLeadPipeline, lead: "l-42"  │
│  => { bid_response: { ... }, observations: [...]}│
│  >> facts "leads", as_of: 3.weeks.ago           │
│  => [#<Fact id=... key="l-42" ...>]             │
│  >> checkpoint "spark-shadow.igm"               │
│  => Image saved (1.2GB, 4.2M facts)             │
└──────────────────────┬──────────────────────────┘
                       │ Magnus FFI / native
┌──────────────────────▼──────────────────────────┐
│              igniter-kernel (Rust)               │
│                                                 │
│  ┌──────────────┐    ┌────────────────────────┐ │
│  │  Fact Memory │    │   Contract Registry    │ │
│  │  ShardedLog  │◄───│   .igapp in-memory     │ │
│  │  128 shards  │    │   hot-reload           │ │
│  └──────┬───────┘    └──────────┬─────────────┘ │
│         │                       │               │
│  ┌──────▼───────────────────────▼─────────────┐ │
│  │              VM Executor                   │ │
│  │  25 opcodes, Decimal, temporal, branching  │ │
│  │  read from TBackend = local function call  │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Image: checkpoint / resume             │   │
│  │  Facts + Contracts + Observations       │   │
│  │  .igm format (Smalltalk image analog)   │   │
│  └─────────────────────────────────────────┘   │
│                                                 │
│  ┌─────────────────────────────────────────┐   │
│  │  Network Bridge (optional)              │   │
│  │  .serve("0.0.0.0:7401") — expose TCP   │   │
│  │  когда нужна сетевая связность          │   │
│  └─────────────────────────────────────────┘   │
└─────────────────────────────────────────────────┘
```

---

## Два варианта не конкурируют — они дополняют

Это точно как SQLite vs PostgreSQL:

| | igniter-kernel (unified) | igniter-tbackend (network) |
|---|---|---|
| Deployment | Single process | Client-server |
| Latency | Sub-microsecond | 0.5–5ms |
| Use case | Dev, embedded, single-node | Shadow, distributed, polyglot |
| Isolation | Shared memory | Network boundary |
| DX | REPL, Image, IDE | TCP REPL (tbackend_repl.rb) |
| Ruby | Magnus FFI | TCP client |

**Shadow production**: остаётся network (isolation критична)
**Development, REPL, igniter-ide**: kernel (DX критичен)
**Spark CRM embedded** (будущее): kernel через FFI

И красота: один и тот же код. `igniter-kernel` может вызвать `.serve()` и стать сетевым сервером. `igniter-tbackend` может встроить VM и стать kernel. Это одна система с двумя режимами развёртывания.

---

## Связь со Spec

`igniter-kernel` — это прямая реализация PROP-006 RuntimeMachine в полном смысле:

```
boot()      → IgniterMachine::new()
load()      → machine.load_contract("path.ig")
evaluate()  → machine.dispatch("Contract", inputs)
checkpoint()→ machine.checkpoint("state.igm")
resume()    → IgniterMachine::resume("state.igm")
```

И `.igm` image file — это первый артефакт который canonical spec описывает абстрактно ("semantic image"), а igniter-lab реализует конкретно. Это сильный contribution назад в canonical через External Pressure channel.

---

**Что думаешь — `igniter-kernel` или `igniter-machine`? И хочешь двигаться сразу к архитектурному дизайну kernel как следующего шага igniter-lab?**
---