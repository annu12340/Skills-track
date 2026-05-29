---
name: semantic-commit-guard
description: >-
  A locally executable pre-commit gateway that inspects the semantic meaning of
  code changes, enforcing architecture, security, and documentation intent before
  anything lands in a repository.
---

# Semantic Commit Guard

Traditional pre-commit hooks catch syntax and lint issues, but they can’t judge
architectural intent, security context, or whether a refactor violates project
standards. This skill acts as an advanced local git hook: it evaluates the
meaning of every staged change and blocks commits that introduce latent debt.

## How it works

- Runs as a pre-commit style check before the commit is finalized.
- Analyzes staged diffs for semantic patterns, not just syntax.
- Asks questions such as:
  - Did this change introduce an exposed API key pattern?
  - Does this refactor violate our project's specific design patterns?
  - Is the documentation updated to reflect the new function or behavior?
- If a violation is found, it rejects the commit and outputs the exact lines
  and guidance needed to fix it.

## Why it wins

- Shifts AI code review from post-merge PR bots to a local, immediate gate.
- Prevents technical debt from entering the repository in the first place.
- Helps keep commits clean, secure, and aligned with project architecture.
- Enables teams to enforce custom semantic policies consistently without
  waiting for manual review.
