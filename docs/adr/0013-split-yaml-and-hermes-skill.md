# Design package is split YAML plus a Hermes skill

Authoritative mechanics live in split YAML under the project (`progression.yaml`, `classes/*.yaml`, `lore.yaml`, weights, etc.). `CONTEXT.md` and `docs/adr/*` hold language and decisions. A Hermes skill loads those files and standardizes plan/build/review coordination with the agent. Markdown-only specs are not the source of truth for numbers.
