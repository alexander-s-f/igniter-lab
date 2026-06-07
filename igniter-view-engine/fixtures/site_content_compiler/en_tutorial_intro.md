---
page_id: tutorial-compiler-first-proof
locale: en
title: "Tutorial: Compiler First Proof"
slug: tutorial/compiler-first-proof
canonical_path: /tutorial/compiler-first-proof/
fallback_locale: ~
---

# Compiler First Proof

This tutorial walks through writing your first compiler proof in Igniter.

## Prerequisites

- Igniter installed locally
- Basic understanding of contracts

## Step 1: Write a contract

```igniter
contract greet(name: String) -> String
```

## Step 2: Run the proof

```bash
igniter proof greet_spec.igv
```

Expected output:

```
PASS greet: 1/1
```

See the [language specification](/language/specification/) for details.
