# Team Layout

## Target Layout

```text
+------------------------+-------------------+-------------------+
|                        |  fe-team-leader   |   fe-developer    |
|                        +-------------------+-------------------+
|  team-lead             |  be-team-leader   |   be-developer    |
|  (main session, 50%)   +-------------------+-------------------+
|                        |  test-team-leader |   test-engineer   |
|                        +---------------------------------------+
|                        |         security-engineer             |
+------------------------+---------------------------------------+
```

## Layout Intent

- `team-lead` occupies the left half of the tmux window (50% width, full height).
- The right half (50% width) is split into four equal-height rows.
- Row 1 (FE): `fe-team-leader` and `fe-developer` side by side, equal width.
- Row 2 (BE): `be-team-leader` and `be-developer` side by side, equal width.
- Row 3 (Test): `test-team-leader` and `test-engineer` side by side, equal width.
- Row 4 (Security): `security-engineer` spans the full right-half width.
- Do not fall back to an even grid layout. If the required layout cannot be applied, report the exact failure and keep the team running.
