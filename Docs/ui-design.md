# UI Design Notes (Napkin Stage)

## Purpose

This document is a working design scratchpad for two related but distinct products:

1. Builder/Testbed UX (developer workflow) - Focusing on this first
2. Operator UX (consumer/admin workflow) - Future

The goal is to keep these surfaces intentionally separate so test orchestration does not leak into normal day-to-day operator experience.

## Practical UX Rules

- UI should only collect inputs and call scripts/CLIs.
- UI should display raw backend outputs first, then a readable summary.
- No duplicated realm logic in Swift; only parameter passing, validation, and state display.
- Every user action should map 1:1 to a backend command sequence you can inspect.

## Baseline Decisions (Current)

1. Node authority model: bootstrap node (`node1`) is the inviter/authority in simple flows.
2. Two audiences:
`Builder` for local multi-node harness controls and logs.
`Operator` for guided realm/vault workflows.
3. Data separation:
testbed data lives under `~/.cyberspace/testbed` and should never share state with normal runtime data.
4. Local testbed default:
single machine, loopback networking, one isolated node env per node.
5. Initial test profile:
3 nodes with unique ports.

## Testbed Topology (Single macOS Machine)

`Test-Me-Realm`

- `node1`: `127.0.0.1:8885`
- `node2`: `127.0.0.1:8884`
- `node3`: `127.0.0.1:8883`

Each node has isolated:

- key directory
- vault/work directory
- env file
- log/pid files

## Lifecycle Surfaces to Model

### Realm and Node Lifecycle

- assign endpoint (IP + port)
- init realm / bootstrap node
- set realm policy
- invite node / accept node
- inspect node state
- mark unreachable / reinstate
- remove node
- monitor node health and access patterns
- test reachability
- federation action (explicitly defined; not “merge” hand-wave)
- disband realm

### Vault Lifecycle

- init vault
- put/update/remove object
- commit/seal operation
- rollback/repair
- monitor storage and access behavior
- archive/restore
- decommission/remove vault

### Who Can Access What?

Intent is not “everyone has access to everything.”
The design intent is capability-based authorization, explicitly not ACL-centric and not ambient/global access:

memo-0045-security-architecture.txt (line 12)
memo-0003-spki-authorization.txt (line 12)
memo-0006-vault-architecture.txt (line 34)
memo-0023-capability-delegation.txt (line 175)
(attenuation example, amplification rejected at memo-0023-capability-delegation.txt (line 181))

So: access should be granted by cert/capability chains; broad access only if someone intentionally delegates broad capability (e.g., vault-root).

Authorization: capability/SPKI controls who is allowed to do operations.
Integrity/audit: signatures + hash chains make tampering detectable.
Encryption at rest: used for sealed archives (e.g., zstd+age), not necessarily every live working file by default.

So if someone has raw OS access, they may still read/modify local files unless you add stronger local protections (disk encryption, encrypted live store, key isolation, process hardening).

What the system should guarantee today is mostly “tampering is detected,” not “OS-level attacker can’t touch bytes.”

If you want “can’t be messed with by OS access,” you need an explicit threat model and controls for local-at-rest encryption + key protection for live vault state, not just archive encryption.

## Capability labels as policy objects

Use a two-layer model:

**Admin defines** named capabilities (examples: story.read, story.write, legal.review).
These are realm policy terms, not OS filesystem ACL entries.

**Certificates reference** those labels
Cert issuance includes capability tags/constraints from that policy set.

**Verification checks** cert chain + attenuation + target capability label.
For files/directories, assign policy metadata, not native OS ACLs:

1) Store a logical capability attribute in vault metadata (for each object/path), e.g. required labels to read/write.
2) Keep this in signed/replicated vault state so behavior is cross-platform and tamper-evident.
3) Optionally mirror to OS xattrs for convenience, but treat xattrs as cache/hint, not source of truth.

So: named capabilities should be admin-configurable, embedded in cert generation, and bound to file/directory objects via vault metadata attributes.

## Security Contract Columns (Per Action)

- `Action`
- `Scope`
- `Initiator Role`
- `Required AuthN`
- `Required AuthZ`
- `Approval Policy`
- `Preconditions`
- `Validation Checks`
- `Data Impact`
- `Replication/Propagation`
- `Audit Event`
- `Audit Fields (minimum)`
- `Failure Behavior`
- `Rollback/Compensation`
- `User Confirmation Required`
- `Idempotency`
- `Rate Limit / Abuse Guard`
- `Observability / Alerts`
- `Compliance / Retention`
- `Notes`

## Product Direction: Builder/Demo Only

### Builder/Testbed UX

Primary job: safely run and observe multi-node local simulations.

Core controls:

- init
- status
- self-join (node1)
- invite others (2..N)
- start node UI instances
- stop node UI instances
- live log tail

### Developer Log Layout (Builder)

Use a readable one-line layout per event:

- `[HH:MM:SS] [LEVEL] <component> <action> -> <result> | <details...>`

Minimum fields to preserve from structured logs:

- timestamp (`ts`) rendered as local `HH:MM:SS`
- severity (`level`)
- component (`component`)
- action (`action`)
- result (`result`)
- request correlation (`request_id`, shortened)
- optional context: `node_id`, `duration_ms`, `message`

Display rules:

- parse JSON log lines into the readable format above
- leave non-JSON lines untouched so raw CLI output is still visible
- keep a `Readable` toggle so developers can switch between formatted and raw logs
- keep an `Expand` toggle so the log pane can grow for deep debugging sessions

## Open Design Decisions

1. Node addressing:
manual port choice vs automatic allocator + collision checks.
2. Invite protocol:
token-only, signed cert bundle, or both.
3. Federation semantics:
what exactly is joined (trust, data, metadata, all?).
4. Policy edit UX:
free-form S-expression vs constrained form editor.
5. Recovery UX:
when to expose hard rollback vs forward-only rollback.
6. Storage local edits:
allow direct filesystem edits or force app-mediated writes only.

## Potential Pitfalls (Callouts)

1. Authority ambiguity:
if invite authority is not explicit, trust decisions become unclear to users.
2. Data bleed:
if testbed and real keys/vaults share dirs, demos can mutate real state.
3. Endpoint collisions:
duplicate ports silently break “multi-node” tests.
4. Weak observability defaults:
no clear logs/status leads to false confidence.
5. Overexposed observability:
metrics/logs can leak sensitive capability or federation information.
6. Undefined federation language:
“merge realms” is too vague for secure implementation.

## Capacity and Replication Policy

If every node stores a full vault by default, smaller endpoints can be overwhelmed. Capacity must be explicit in admission and replication policy.

### Node Storage Roles

- `full`: holds full active vault for the realm.
- `witness`: stores metadata + audit + small hot subset; no full payload guarantee.
- `archiver`: optimized for retention, cold storage, and restore operations.
- `edge`: minimal local cache; relies on fetch-on-demand.

### Admission Controls (Before Join)

- check declared disk budget and current free space
- estimate dataset size and projected growth window
- reject join as `full` if capacity headroom is below threshold
- allow role downgrade (for example, `full -> witness`) with explicit user confirmation

### Replication Strategy

- replicate metadata/audit globally first so trust state is consistent
- replicate payloads by role policy (`full` gets all; `witness` gets bounded subset)
- support backfill on role upgrade with rate limits

### Quotas and Guardrails

- per-node hard quota (`max_bytes`)
- per-realm soft quota warnings
- per-sync transfer cap (`max_sync_bytes`) to avoid one-shot saturation
- backpressure signal when node is near exhaustion

### Retention and Pruning

- define retention classes: `hot`, `warm`, `cold`
- permit automatic pruning only for non-authoritative caches (`edge`/`witness`)
- keep audit chain and capability metadata non-prunable except by explicit policy

### UI Requirements

- show "join impact" preview before admit: expected disk + network footprint
- show role mismatch warnings when policy asks for more than capacity allows
- expose one-click "safe downgrade" for constrained nodes

### Practical Defaults

- local 3-node testbed: `node1=full`, `node2=full`, `node3=witness`
- production baseline: require at least 2 `full` nodes before enabling aggressive retention/pruning on other node classes.
- production baseline: enforce continuous capacity health checks and alert when headroom drops below threshold.

## “realm setup/admin” should be a capability too

Recommended model:

- `realm.bootstrap`  
  can create initial realm policy and root trust anchor
- `realm.admin.invite`  
  can issue join/admin invitations
- `realm.admin.policy`  
  can modify capability taxonomy and delegation limits
- `realm.admin.membership`  
  can suspend/reinstate/remove nodes
- `realm.admin.storage`  
  can change replication/placement/retention rules

And yes, you can bring in other admins by issuing delegated admin certs with scoped powers and expiry. You usually want:

- least privilege
- short-lived admin certs
- dual-control for dangerous actions (`2-of-N` approval)

On your clustering assumption: treat this less like old VMS-style “everything active everywhere,” and more like modern distributed systems:

- control plane: identity, policy, membership, audit (highly replicated, strongly validated)
- data plane: object payloads (replicated by policy/role/capacity, not necessarily on every node)

What large companies usually do for physically distributed server admin:

- centralized identity + RBAC/capability-style delegation
- infrastructure as code for policy/config rollout
- environment separation (prod vs testbed hard-isolated)
- quorum workflows for critical changes
- tiered replication (hot/warm/cold), not full copy on every node
- placement policies by region/latency/compliance
- immutable audit trails + continuous monitoring/alerting

So your UI/admin model should expose:

- admin capability templates
- delegated admin issuance/revocation
- quorum-required actions
- placement/replication policy by node role and capacity.

## Scenario Sketches

### Single Realm, Role-Based Nodes (Journalism)

- Node 1: Root Admin (policy + invites)
- Node 2: Editor Desk
- Node 3: Reporter
- Node 4: Fact-Check
- Node 5: Legal
- Node 6: Final/Archive

### Multi-Realm by Function

- Realm A: editorial approvals
- Realm B: reporting workspace
- Realm C: fact-check
- Realm D: legal review
- Realm E: final publishing
- Realm F: archive retention

## Related Memo Index

See `spki/macos/swiftui/Docs/ui-memo-reference.md` for lifecycle-relevant memo links and quote excerpts from `spki/scheme/docs/notes/index.html`.
