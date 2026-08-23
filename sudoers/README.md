# install-sudoers.sh

## Purpose

`install-sudoers.sh` is the single authoritative installer for sudoers
configuration on this host.

It installs all sudoers fragments found in:

    /home/ecloaiza/sudoers

into:

    /etc/sudoers.d/

The script validates each fragment and the full sudo configuration before
completion and performs a rollback if any error occurs.

This design ensures:
- no partial sudo configuration
- no sudo lockouts
- explicit, auditable changes


## Source of Truth

Sudoers fragments are stored in:

    /home/ecloaiza/sudoers

Only files matching the pattern:

    NN-*

(e.g. `00-defaults`, `10-admin`) are installed.

The following files are intentionally ignored:
- README.md
- legacy files (e.g. `ecloaiza-nopasswd`)


## What the Script Does

1. Discovers sudoers fragments in `/home/ecloaiza/sudoers`
2. Creates a timestamped backup of existing `/etc/sudoers.d` fragments
3. Installs each fragment with correct permissions:
   - owner: root
   - mode: 0440
4. Validates each fragment using `visudo -cf`
5. Validates the full sudo configuration using `visudo -c`
6. Rolls back automatically if any step fails


## Execution

Run as the regular user:

    /home/ecloaiza/scripts/linux/install-sudoers.sh

The script uses `sudo` internally where required.


## Logging

This script itself does not log execution output.

However, sudoers fragments may enable:
- sudo I/O logging
- per-script execution logging
- journald logging

Refer to sudoers fragment documentation for logging behavior.


## Safety Guarantees

- No in-place editing of `/etc/sudoers`
- No partial installs
- No silent failures
- Explicit validation at every stage


## Requirements

- `sudo`
- `visudo`
- Write access to `/etc/sudoers.d` via sudo


## Notes

- This script is intentionally single-purpose.
- Do not add unrelated logic.
- Any changes to sudoers behavior must be done via fragments in
  `/home/ecloaiza/sudoers`, not by modifying this script.

## Author

ELIKESBIKES (Tars)
