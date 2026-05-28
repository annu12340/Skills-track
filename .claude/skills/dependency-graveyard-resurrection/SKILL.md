---
name: dependency-resurrection-engine
description: >-
  A migration-focused MCP skill that resurrects legacy dependency stacks by
  parsing manifests, cross-referencing changelogs and error reports, and
  iteratively updating code and packages until the project builds again.
---

# Dependency Resurrection Engine

Upgrading a major framework can trigger cascading breakage across dozens of
third-party packages. This skill handles the full migration lifecycle: from
dependency analysis to targeted code changes and repeat builds.

## How it works

- Parses `package.json`, `requirements.txt`, or other dependency manifests.
- Cross-references current package versions with live changelogs, upgrade notes,
  and known error databases.
- Generates a targeted execution script that attempts to build the project.
- When a peer dependency or API mismatch causes a compilation failure, it
  analyzes the log, updates the affected code to the new API syntax, updates
  the dependency tree, and retries the build automatically.
- Continues this cycle until the project successfully builds or the upgrade
  boundaries are identified.

## The "Wow" factor

- Treats upgrades as an autonomous migration process rather than a manual
  checklist.
- Detects specific peer dependency failures and correlates them with code-level
  fixes.
- Automatically rewrites code for new API versions when needed.
- Retires the need for error-prone, one-off upgrade attempts by making the
  process repeatable and verifiable.
