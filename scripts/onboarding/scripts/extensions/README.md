# GNOME Extensions Management

This directory implements **state-based GNOME Extensions management**.

## Philosophy

This system does **NOT** blindly install extensions.

Instead, it:
- Declares desired state
- Reconciles current system state
- Verifies correctness

This is safe for:
- Greenfield systems
- Existing systems
- Repeated runs

---

## Components

### Option A — Baseline
`extensions.conf` defines:
- Extension UUID
- Desired state (enabled / disabled)

This file is the **source of truth**.

---

### Option B — Reconcile
`install_extensions.sh`:
- Detects installed extensions
- Enables or disables as needed
- Never reinstalls
- Never removes packages

---

### Option C — Verify
`verify_extensions.sh`:
- Audit-only
- Reports drift
- Non-destructive

---

## Supported Systems

- Ubuntu 24.04 (validated)
- Arch Linux (compatible, not auto-installing)

---

## Notes

- System extensions are respected
- User extensions are managed safely
- Installation logic may be added later

---
Author: ELIKESBIKES (Tars)
Or Gargantua
