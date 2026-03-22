# install-sudoers.sh

## Purpose

This script is the single authoritative installer for sudoers configuration on this host.

It installs all sudoers fragments found in:

    /home/ecloaiza/sudoers

into:

    /etc/sudoers.d/

The script validates each fragment and the full sudo configuration before completion and performs an automatic rollback on failure.


## Why this exists

- Avoids editing /etc/sudoers directly
- Prevents partial sudo configuration
- Prevents sudo lockouts
- Provides auditable, repeatable changes


## Source of Truth

Sudoers fragments live in:

    /home/ecloaiza/sudoers

Only files matching the pattern:

    NN-*

are installed (example: `00-defaults`, `10-admin`).

All other files (README.md, legacy configs) are ignored.


## What the Script Does

1. Discovers sudoers fragments
2. Backs up existing `/etc/sudoers.d` entries
3. Installs each fragment with mode `0440`
4. Validates each fragment using `visudo -cf`
5. Validates the full sudo configuration
6. Rolls back automatically on error


## Execution

Run as the regular user:

    /home/ecloaiza/scripts/linux/sudoers/install-sudoers.sh

The script uses sudo internally where required.


## Logging

Sudo execution logging is controlled by sudoers fragments
(e.g. `00-defaults`, `40-scripts`).

This script itself does not write logs.


## Notes

- This script is intentionally single-purpose.
- Do not modify sudo behavior here.
- All policy changes must be done via `/home/ecloaiza/sudoers`.


## Author

ELIKESBIKES (Tars)
