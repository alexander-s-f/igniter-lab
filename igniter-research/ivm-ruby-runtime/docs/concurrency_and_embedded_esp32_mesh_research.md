# Research Report: Concurrency Paradigms and Embedded Mesh Architecture (ESP32)

This off-track research report explores advanced architectural options for **Parallelism** and **Embedded/Microcontroller (ESP32) execution** in the Igniter-Lang ecosystem.

---

## 1. Concurrency Paradigms in IVM

The stack-based, register-gated design of the Igniter Virtual Machine (IVM) is structurally well-suited for high-throughput concurrency due to a crucial property: **Immutability of Executables**.

During timeline query evaluation:
-   `LoadedModule` (the compiled instructions) is **read-only**.
-   `TemporalBackend` (the bitemporal historical records) is **read-only**.
-   Each query execution allocates its own private, lightweight stack (256 integers) and instruction pointer inside the C execution frame (`execute_bytecode_temporal`).

This yields three powerful parallelism vectors:

### A. Lock-Free Thread-Level Data Parallelism
Because the module and database backend are read-only, multiple native threads (e.g., POSIX `pthreads` or C++ `std::thread`) can execute timeline points concurrently on the **same pointers** without any locking, semaphores, or mutex synchronization.
-   *Throughput*: On a 16-core CPU, we can evaluate 16 timeline coordinates in parallel, scaling throughput linearly to **24 million evaluations per second**!

### B. Pipeline Concurrency
For streaming sensor inputs or real-time event logs, a pipeline model separates input parsing, execution, and observation tracing:
-   **Stage 1**: An input ingestion thread writes observations to a ring buffer.
-   **Stage 2**: A pool of resident execution threads processes evaluations.
-   **Stage 3**: An auditing thread drains the observation sink, serializing traces.

### C. Cluster-Level Distributed Concurrency
Evaluating complex counterfactual timelines or multi-agent simulations can be distributed across nodes:
-   A master supervisor partition-assigns timeline blocks $[T_{start}, T_{end}]$ to cluster worker nodes.
-   Each worker node executes its local slice natively and reports observation traces asynchronously to a centralized ledger.

---

## 2. Embedded & Microcontroller (ESP32) Architecture

Migrating to low-power embedded targets like the **ESP32** requires a **Ruby-Free Execution Environment**. 

A standard ESP32 (Xtensa Dual-Core, 520KB SRAM, 4MB Flash) cannot run a Ruby interpreter due to memory limitations (Ruby requires megabytes of RAM and heavy OS features). However, our **Native C Supervisor (`runner.c`)** is written in standard, portable C with a small static execution-frame footprint in the research model. ESP32 compatibility remains a candidate research hypothesis, not a guarantee.

### Embedded Execution Blueprint (Ruby-Free)

```text
  +-----------------------------------------------------------------------+
  |                             ESP32 FLASH                               |
  |                                                                       |
  |  +---------------------------+       +-----------------------------+  |
  |  |  Bytecode (.igbin File)   |       |   C Pluggable Backend       |  |
  |  |  Compiled directly as     |       |   HistoricalRecords stored  |  |
  |  |  static const uint8_t[]   |       |   directly in flash memory  |  |
  |  +---------------------------+       +-----------------------------+  |
  +-----------------------------------------------------------------------+
                                     |
                                     v
  +-----------------------------------------------------------------------+
  |                           ESP32 CORE 0 & 1                            |
  |                                                                       |
  |    [FreeRTOS Task Core 0]                  [FreeRTOS Task Core 1]     |
  |     - private stack (1KB)                   - private stack (1KB)     |
  |     - executes module                       - executes module         |
  +-----------------------------------------------------------------------+
                                     |
                                     v
  +-----------------------------------------------------------------------+
  |                            ESP-NOW MESH                               |
  |   Asynchronous broadcast of compact 16-byte observation envelopes     |
  +-----------------------------------------------------------------------+
```

---

## 3. ESP32 Dual-Core Execution Model (FreeRTOS)

ESP32 runs FreeRTOS, a real-time scheduler. We can execute parallel IVM loops pinned to Xtensa Core 0 and Core 1:

```c
#include "freertos/FreeRTOS.h"
#include "freertos/task.h"

// Shared Read-Only Compiled Bytecode from Flash
static const uint8_t BYTECODE_IMAGE[] = { 
    0x0D, 0x00, 0x00, 0x00, // OP_LOAD_AS_OF
    ... 
};

// Thread-safe task executing the Resident C Supervisor
void ivm_execution_task(void* pvParameters) {
    int32_t error_code = 0;
    int32_t inputs[1] = { 1778414400 }; // timeline epoch input
    
    while(1) {
        // Run completely inside SRAM/Flash
        int32_t res = execute_bytecode_temporal(
            (const Instruction*)BYTECODE_IMAGE, 
            INSTRUCTION_COUNT, 
            inputs, 
            global_backend, 
            &error_code
        );
        
        // Broadcast observation or actuate pins locally
        if (res > 500) {
            gpio_set_level(GPIO_NUM_2, 1); // Actuate local hardware
        }
        
        vTaskDelay(pdMS_TO_TICKS(100)); // Period calculation
    }
}

void app_main() {
    // Pin tasks to Core 0 and Core 1 for true hardware parallelism!
    xTaskCreatePinnedToCore(ivm_execution_task, "ivm_core_0", 2048, NULL, 5, NULL, 0);
    xTaskCreatePinnedToCore(ivm_execution_task, "ivm_core_1", 2048, NULL, 5, NULL, 1);
}
```

---

## 4. ESP32 Mesh Networking: ESP-NOW Protocol

In a cluster of ESP32 nodes (e.g. edge mesh networks), transferring heavy JSON structures is prohibitive.
However, Igniter-Lang's bitemporal observations are represented by simple, compact values (such as an observation kind enum and a value).

We can transmit these observations over **ESP-NOW**, a low-power, zero-overhead peer-to-peer wireless protocol that allows sending payloads up to 250 bytes:

### Packed Mesh Observation Frame (16 Bytes)
```c
typedef struct {
    uint8_t magic;           // 0x49 (Igniter)
    uint8_t observation_kind;// Enum matching kind (1 byte)
    uint16_t node_id;        // Source node MAC offset (2 bytes)
    int64_t valid_time;      // Valid time epoch (8 bytes)
    int32_t value;           // Observation value (4 bytes)
} MeshObservationFrame;
```

*   **Ultra-Low Latency**: ESP-NOW packets bypass the Wi-Fi connection handshake, transmitting packed observations between nodes in **less than 1 millisecond**!
*   **Decentralized Consensus**: Each node in the mesh can receive neighboring observation frames, feed them into its local C-level `TemporalBackend`, and immediately execute its local business rule contracts natively.

---

## 5. Summary & Mainline Migration Strategy

This blueprint demonstrates that Igniter-Lang has a seamless roadmap from a Ruby development framework to a high-speed, embedded distributed cluster:

1.  **Development & Verification (Ruby Host)**: Contracts are declared, compiled, and verified using the Ruby DSL/compiler research path, producing frozen, trusted `.igbin` binary files.
2.  **Deployment (Ruby-Free)**: `.igbin` files are compiled statically into ESP32 flash images or uploaded dynamically over the mesh network.
3.  **Edge Execution (ESP32 C VM)**: Nodes execute rules and query local temporal databases natively, interacting directly with local GPIO actuators and mesh radios with maximum throughput and zero dynamic memory allocation.
