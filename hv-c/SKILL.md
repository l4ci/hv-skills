---
name: hv-c
description: Shortcut for /hv-capture — forwards verbatim. See hv-capture for behavior.
user-invocable: true
---

# hv-c

Alias for `/hv-capture`. Invoke the `hv-capture` skill via the `Skill` tool, passing the user's arguments verbatim. Do not duplicate logic here. `/hv-capture` prints its own banner; `/hv-c` does not print one of its own so the user sees a single banner per invocation.
