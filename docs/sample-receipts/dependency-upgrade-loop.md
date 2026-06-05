# Rescue Receipt: dependency-upgrade-loop

- Created: 2026-05-31T000000Z
- Repo: demo-repos/dependency-upgrade-loop-demo
- Branch / starting commit: main @ HEAD
- Outcome: GREEN

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `git status --porcelain` | Inventory user work before editing dependencies. | Clean after demo setup. |
| `bash verify.sh` | Establish baseline verification. | Fails before migration on modern packages. |
| `python -m pip index versions pydantic` | Inspect available Pydantic versions. | Confirms Pydantic v2 target. |
| `python -m pip index versions pydantic-settings` | Find package needed for moved `BaseSettings`. | Confirms separate settings package. |
| `<build-probe> --cmd "bash verify.sh" --log /tmp/dep-upgrade.log` | Verify after each migration step. | Final run passes. |

## Evidence Found
- Baseline verification: `bash verify.sh` imports `app.settings` and runs tests.
- Upgrade notes checked: Pydantic v2 migration notes for `BaseSettings` and serializer changes.
- Root errors cleared: `BaseSettings` moved out of `pydantic`; `.dict()` is replaced by `.model_dump()`.
- Final verification: `bash verify.sh` exits 0.

## Files Changed
- `requirements.txt`: dependency versions updated, with `pydantic-settings` added.
- `app/settings.py`: imports `BaseSettings` from `pydantic_settings`.
- `app/settings.py`: replaces `Settings().dict()` with `Settings().model_dump()`.
- `.repo-rescue/receipts/<timestamp>-dependency-upgrade-loop.md`

## Culprit Dependency / Boundary
- Pydantic `1.10.2 -> 2.x` is the main compatibility boundary.
- `BaseSettings` moved to `pydantic-settings`, so the migration requires adding a package, not just changing imports.

## AI Reasoning Excerpt

> The first root error in the build log was `ImportError: cannot import name 'BaseSettings' from 'pydantic'`. Before writing any code I checked the [Pydantic v2 migration guide](https://docs.pydantic.dev/latest/migration/), which documents that `BaseSettings` was intentionally removed from the core `pydantic` package and moved to the separate `pydantic-settings` package. This is not a renamed import — it requires adding a new dependency.
>
> I applied one change at a time: first added `pydantic-settings` to `requirements.txt` and updated the import in `app/settings.py`. After rebuilding, the second root error was `AttributeError: 'Settings' object has no attribute 'dict'` — Pydantic v2 renamed `.dict()` to `.model_dump()`. I fixed that in isolation and rebuilt.
>
> **Behavior change flagged**: Pydantic v2 changes how validation errors are structured. If `app/client.py` catches `pydantic.ValidationError` and inspects `.errors()`, the field names in the error dict changed format. I could not verify this from the demo tests alone — **human review of error handling paths is recommended before merging.**

## Remaining Risk
- The demo verification only covers imports and the settings test.
- Runtime HTTP behavior in `app/client.py` is not exercised beyond import.

## Recommended Next Action
- Run broader project tests if available, then review the dependency diff and behavior changes before merging.
