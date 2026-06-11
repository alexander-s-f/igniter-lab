# Date, Time, and Calendar Semantics in Igniter v0

**Status:** DRAFT / GOVERNANCE  
**Topic:** Temporal Operations, Determinism, String Parsing  
**Date:** 2026-06-11  

## 1. The Core Philosophy: Determinism Over Convenience

In most mainstream programming languages, date and time functions are the leading cause of non-deterministic behavior and host-environment leakage. A function that behaves one way in London on Tuesday may behave differently in New York on Wednesday due to implicit timezone resolutions, locale-specific formatting preferences, and the ambient system clock.

Igniter’s entire execution model relies on pure, replayable, deterministic contracts. Therefore, the standard library handles temporal boundaries with extreme rigidity.

---

## 2. The Ambient Clock Ban (`OOF-L6`)

The most famous rule of Igniter's temporal model is `OOF-L6`, which explicitly bans the `now()` function from the standard library core. 

### Why `now()` is Forbidden
If a contract calls `now()` to determine if an invoice is overdue, the result of that contract will silently change depending on when it is evaluated. This destroys the auditability of the ledger/state machine.

### The Solution: Temporal Context Injection
Time must never be "read" from the system; it must be passed as an argument. The engine provides a `TemporalCtx` (e.g., the block timestamp, or the HTTP request received time), which is passed down the evaluation tree. Time is just another immutable input.

---

## 3. Parsing Strings into Dates

Parsing a string like `"10/11/12"` is a semantic nightmare. Depending on the server's locale, this could be October 11, 2012, or November 10, 2012. 

### Proposed Policy: ISO-8601 Exclusivity
To maintain computational purity without shipping a massive, volatile Locale Database (tzdata) inside the compiler, the Igniter `stdlib` should only support parsing **strict ISO-8601** strings (or RFC-3339 equivalents). 

```igniter
-- VALID
let valid_date = stdlib.temporal.parse("2026-06-11T21:35:12Z") 

-- INVALID (OOF-TY0 or Runtime Error)
let invalid = stdlib.temporal.parse("June 11, 2026")
```

If an application requires parsing human-readable or localized dates, that transformation must happen at the **application edge** (e.g., in a frontend client or an API gateway) before the payload crosses the Igniter pure boundary. The pure domain should only receive unambiguous data.

---

## 4. Date Arithmetic and Timezones

Igniter supports pure calendar arithmetic via the `stdlib.temporal` namespace (e.g., `add_days`, `diff_days`, `beginning_of`).

### The Danger of Daylight Saving Time (DST)
`add_days(d, 1)` on a `Timestamp` is dangerous if the local timezone observes DST, because a "day" could be 23, 24, or 25 hours long. 

### Proposed Policy: Absolute vs Logical Time
1. **`Timestamp` (Physical Time):** Represents absolute elapsed seconds since the UNIX epoch. Operations on `Timestamp` should only be linear (e.g., `add_seconds`, `diff_seconds`).
2. **`Date` / `DateTime` (Logical/Calendar Time):** Represents a point on a human calendar. `add_days` is a purely logical operation on the calendar grid. 

Igniter avoids implicit local timezones entirely. All `DateTime` logic assumes UTC unless an explicit, rigid timezone offset (e.g., `+03:00`) is supplied during the operation. 

---

## 5. Summary of Permitted Operations (v0)

From `ch8-stdlib.md`:
*   `add_days(d: Date, n: Integer) -> Date`
*   `diff_days(a: Date, b: Date) -> Integer`
*   `beginning_of(d: Date, grain: Symbol) -> Date`
*   `end_of(d: Date, grain: Symbol) -> Date`
*   `day_of_week(d: Date) -> Integer`

All operations act as pure mathematical functions on a fixed calendar grid, free from ambient host disruption.
