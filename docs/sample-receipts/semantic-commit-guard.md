# Rescue Receipt: semantic-commit-guard

- Created: 2026-05-31T000000Z
- Repo: demo-repos/commit-guard-demo
- Branch / commit reviewed: main @ HEAD, staged index
- Outcome: BLOCKED

## Commands Run
| Command | Purpose | Result |
|---|---|---|
| `git diff --cached --stat` | Confirm staged files exist. | `app/config.py`, `app/handlers.py`, and `README.md` staged. |
| `git rev-parse --show-toplevel` | Identify repo root. | `demo-repos/commit-guard-demo`. |
| `git diff --cached --name-status` | List staged paths. | Three modified files. |
| `git diff --cached -U0 --no-ext-diff` | Map findings to staged lines. | Exact added-line evidence collected. |
| `git show :app/config.py` | Inspect staged config blob without reading unstaged content. | Hardcoded credentials found. |

## Evidence Found
- Policy sources: `.semantic-guard.md`.
- Staged files reviewed: `app/config.py`, `app/handlers.py`, `README.md`.
- BLOCK `app/config.py`: hardcoded API key and DB password values were staged. Values redacted.
- BLOCK/WARN `app/handlers.py`: raw SQL and business logic moved into the thin handler layer, violating project policy.
- WARN `app/handlers.py`: debug print left on the request path.
- WARN `README.md`: docs claim no secrets are stored while staged source contains credentials.

## AI Reasoning Excerpt

> `app/config.py:14` — I flagged `OPENAI_API_KEY = 'sk-live-...'` as a **high-confidence live credential** for three reasons: (1) the variable name matches the `api_key` / `token` / `secret` pattern in the policy; (2) the value has measured entropy of ~4.6 bits/char, above the 3.5 threshold that separates random secrets from readable strings; and (3) the `sk-live-` prefix is a known OpenAI production key prefix, not a test prefix (`sk-test-`). I redacted the value in this receipt and in the verdict output. **The credential must be rotated regardless of whether this commit is abandoned** — writing it to a file the user controls is sufficient for it to be considered exposed.
>
> `app/handlers.py:22` — Business logic moved into the handler layer. `.semantic-guard.md` explicitly states *"Route handlers must remain thin and delegate all business logic to service classes."* The diff adds `payment_gateway.charge(order.total)` directly to `checkout()`, which is the exact pattern the policy prohibits. I treated this as a **BLOCK** (policy violation) rather than a **WARN** (heuristic) because the rule is documented.
>
> `README.md` — The staged README edit adds the line *"No secrets are stored in this repository"* while `app/config.py` (also staged in this commit) contains a hardcoded credential. This is a docs-sync contradiction, upgraded to **WARN** because the claim directly contradicts the blocked finding above.

## Files Changed
- `.repo-rescue/receipts/<timestamp>-semantic-commit-guard.md`

## Culprit / Root Cause
- A staged change bypassed environment-based secrets, moved service/database logic into the handler, and updated docs in a way that contradicts the code.

## Remaining Risk
- Only the staged index was reviewed. Unstaged local edits, generated files, and repository history were not scanned.
- Any real credential matching the staged values must be rotated even if the commit is abandoned.

## Recommended Next Action
- Move credentials back to environment variables, restore database access to `app/service.py`, remove debug output, update the README, and rotate any plausible live secret.
