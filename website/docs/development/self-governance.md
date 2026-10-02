---
id: self-governance
title: Self-Governance
sidebar_position: 3
---

# Self-Governance

`tenant-emit` is a governed project. Its own source code and architecture are governed by a specification corpus located in the `specs/` directory.

## The Dogfooding Pattern

The project uses the `spec-spine` compiler to govern itself, a pattern known as dogfooding.

The `spec-spine` compiler is pinned as a devDependency in the repository.

## Compiling the Corpus

During CI, and before committing changes to the specifications, the corpus must be compiled and linted.

```bash
# Install the exact governance CLI pin
make tools

# Compile the specs
.bin/spec-spine compile

# Check the index
.bin/spec-spine index check

# Lint the corpus
.bin/spec-spine lint --fail-on-warn
```

This process generates the derived artifacts in the `.derived/` directory. These artifacts are committed to the repository to provide a deterministic, cross-platform proof of the specification state.

## Determinism

The CI pipeline includes a determinism workflow that runs `spec-spine compile` on multiple operating systems (Linux x86_64, Linux aarch64, macOS arm64, Windows x86_64) and asserts that the resulting derived JSON trees are byte-for-byte identical across all platforms.
