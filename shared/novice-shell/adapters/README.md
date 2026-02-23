# Platform Adapters

Thin wrappers for terminal/input/output/process behavior by OS.

Expected design:
- shared command grammar and semantics stay in overlay
- adapters only translate host I/O and environment details
