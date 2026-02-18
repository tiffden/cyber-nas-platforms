# UI Memo Reference (Lifecycle-Oriented)

This reference pulls lifecycle-relevant memos from:

- index: `spki/scheme/docs/notes/index.html`
- memo files: `spki/scheme/docs/notes/memo-*.{txt,ps,pdf,html}`

Each memo in the notes index publishes four formats (`PDF`, `PostScript`, `Text`, `HTML`).

## How To Use This

Use these memos as source material when defining:

- realm/node lifecycle operations
- vault lifecycle operations
- security contract rows
- failure and observability behavior
- federation boundaries and opsec constraints

## Core Lifecycle Memos

### Memo 0002 - Architecture

- Why relevant:
defines node model, quorum behavior, and vault-as-core abstraction.
- Links:
`spki/scheme/docs/notes/memo-0002-architecture.pdf`
`spki/scheme/docs/notes/memo-0002-architecture.ps`
`spki/scheme/docs/notes/memo-0002-architecture.txt`
`spki/scheme/docs/notes/memo-0002-architecture.html`
- Quote:

> "Out of many, one. The VAXcluster motto: N nodes behave as one system."

- Source:
`spki/scheme/docs/notes/memo-0002-architecture.txt:19`

### Memo 0003 - Public Key Authorization

- Why relevant:
defines principal model and delegation-chain verification.
- Links:
`spki/scheme/docs/notes/memo-0003-spki-authorization.pdf`
`spki/scheme/docs/notes/memo-0003-spki-authorization.ps`
`spki/scheme/docs/notes/memo-0003-spki-authorization.txt`
`spki/scheme/docs/notes/memo-0003-spki-authorization.html`
- Quote:

> "Principals are identified by cryptographic keys, not names."

- Source:
`spki/scheme/docs/notes/memo-0003-spki-authorization.txt:13`

### Memo 0005 - Audit Trail

- Why relevant:
defines tamper-evident logging requirements and accountability model.
- Links:
`spki/scheme/docs/notes/memo-0005-audit-trail.pdf`
`spki/scheme/docs/notes/memo-0005-audit-trail.ps`
`spki/scheme/docs/notes/memo-0005-audit-trail.txt`
`spki/scheme/docs/notes/memo-0005-audit-trail.html`
- Quote:

> "Traditional logging cannot answer these questions with certainty. Cyberspace audit trails can."

- Source:
`spki/scheme/docs/notes/memo-0005-audit-trail.txt:29`

### Memo 0006 - Vault Architecture

- Why relevant:
covers vault operations with sealing, authorization, archival, and audit.
- Links:
`spki/scheme/docs/notes/memo-0006-vault-architecture.pdf`
`spki/scheme/docs/notes/memo-0006-vault-architecture.ps`
`spki/scheme/docs/notes/memo-0006-vault-architecture.txt`
`spki/scheme/docs/notes/memo-0006-vault-architecture.html`
- Quote:

> "The Vault wraps Git with: ... SPKI certificates for authorization ... Integrated audit trail for non-repudiation"

- Source:
`spki/scheme/docs/notes/memo-0006-vault-architecture.txt:31`

### Memo 0007 - Replication Layer

- Why relevant:
defines replication guarantees, authorization expectations, and audit on sync/publication.
- Links:
`spki/scheme/docs/notes/memo-0007-replication-layer.pdf`
`spki/scheme/docs/notes/memo-0007-replication-layer.ps`
`spki/scheme/docs/notes/memo-0007-replication-layer.txt`
`spki/scheme/docs/notes/memo-0007-replication-layer.html`
- Quote:

> "Audit Everything - All replication events are recorded in tamper-evident log"

- Source:
`spki/scheme/docs/notes/memo-0007-replication-layer.txt:68`

### Memo 0012 - Federation Protocol

- Why relevant:
defines cross-vault behavior (decentralized peer sync) and consistency tradeoffs.
- Links:
`spki/scheme/docs/notes/memo-0012-federation.pdf`
`spki/scheme/docs/notes/memo-0012-federation.ps`
`spki/scheme/docs/notes/memo-0012-federation.txt`
`spki/scheme/docs/notes/memo-0012-federation.html`
- Quote:

> "Federation provides: ... Decentralized - No master server ... Eventual consistency - Convergence without coordination"

- Source:
`spki/scheme/docs/notes/memo-0012-federation.txt:51`

### Memo 0017 - Versioning and Rollback

- Why relevant:
defines safe rollback semantics and audit requirements for recovery UX.
- Links:
`spki/scheme/docs/notes/memo-0017-versioning-rollback.pdf`
`spki/scheme/docs/notes/memo-0017-versioning-rollback.ps`
`spki/scheme/docs/notes/memo-0017-versioning-rollback.txt`
`spki/scheme/docs/notes/memo-0017-versioning-rollback.html`
- Quote:

> "NOT a git reset. History preserved. Rollback is a forward operation."

- Source:
`spki/scheme/docs/notes/memo-0017-versioning-rollback.txt:114`

### Memo 0023 - Capability Delegation Patterns

- Why relevant:
defines attenuation, revocation, threshold operations, and delegation limits.
- Links:
`spki/scheme/docs/notes/memo-0023-capability-delegation.pdf`
`spki/scheme/docs/notes/memo-0023-capability-delegation.ps`
`spki/scheme/docs/notes/memo-0023-capability-delegation.txt`
`spki/scheme/docs/notes/memo-0023-capability-delegation.html`
- Quote:

> "Capabilities flow through delegation chains with monotonically decreasing authority."

- Source:
`spki/scheme/docs/notes/memo-0023-capability-delegation.txt:13`

### Memo 0024 - Key Ceremony Protocol

- Why relevant:
defines trust-root creation process for realm bootstrap and high-trust operations.
- Links:
`spki/scheme/docs/notes/memo-0024-key-ceremony.pdf`
`spki/scheme/docs/notes/memo-0024-key-ceremony.ps`
`spki/scheme/docs/notes/memo-0024-key-ceremony.txt`
`spki/scheme/docs/notes/memo-0024-key-ceremony.html`
- Quote:

> "Key ceremonies establish roots of trust through transparent, auditable, multi-party processes."

- Source:
`spki/scheme/docs/notes/memo-0024-key-ceremony.txt:13`

### Memo 0030 - Error Handling and Recovery

- Why relevant:
defines deterministic recovery expectations and error auditing.
- Links:
`spki/scheme/docs/notes/memo-0030-error-handling.pdf`
`spki/scheme/docs/notes/memo-0030-error-handling.ps`
`spki/scheme/docs/notes/memo-0030-error-handling.txt`
`spki/scheme/docs/notes/memo-0030-error-handling.html`
- Quote:

> "Errors are first-class objects in the soup, enabling systematic analysis and automated recovery."

- Source:
`spki/scheme/docs/notes/memo-0030-error-handling.txt:12`

### Memo 0033 - Monitoring and Observability

- Why relevant:
defines safe observability requirements and constraints.
- Links:
`spki/scheme/docs/notes/memo-0033-monitoring.pdf`
`spki/scheme/docs/notes/memo-0033-monitoring.ps`
`spki/scheme/docs/notes/memo-0033-monitoring.txt`
`spki/scheme/docs/notes/memo-0033-monitoring.html`
- Quote:

> "Observability data is itself content-addressed and auditable."

- Source:
`spki/scheme/docs/notes/memo-0033-monitoring.txt:13`

### Memo 0038 - Quorum Protocol with Homomorphic Voting

- Why relevant:
useful for governance-level lifecycle actions (disband, critical policy changes).
- Links:
`spki/scheme/docs/notes/memo-0038-quorum-voting.pdf`
`spki/scheme/docs/notes/memo-0038-quorum-voting.ps`
`spki/scheme/docs/notes/memo-0038-quorum-voting.txt`
`spki/scheme/docs/notes/memo-0038-quorum-voting.html`
- Quote:

> "Voting systems that sacrifice any of these properties enable manipulation; true collective decision requires all four."

- Source:
`spki/scheme/docs/notes/memo-0038-quorum-voting.txt:32`

### Memo 0045 - Security Architecture

- Why relevant:
top-level security model and principles used by UI security decisions.
- Links:
`spki/scheme/docs/notes/memo-0045-security-architecture.pdf`
`spki/scheme/docs/notes/memo-0045-security-architecture.ps`
`spki/scheme/docs/notes/memo-0045-security-architecture.txt`
`spki/scheme/docs/notes/memo-0045-security-architecture.html`
- Quote:

> "Authorization flows through signed certificates. No labels, no ACLs, no ambient authority."

- Source:
`spki/scheme/docs/notes/memo-0045-security-architecture.txt:12`

### Memo 0054 - Federation Operational Security

- Why relevant:
defines data-leakage and metadata-exposure concerns for federated operations.
- Links:
`spki/scheme/docs/notes/memo-0054-federation-opsec.pdf`
`spki/scheme/docs/notes/memo-0054-federation-opsec.ps`
`spki/scheme/docs/notes/memo-0054-federation-opsec.txt`
`spki/scheme/docs/notes/memo-0054-federation-opsec.html`
- Quote:

> "Share the minimum information needed for federation to work. Everything else is unnecessary exposure."

- Source:
`spki/scheme/docs/notes/memo-0054-federation-opsec.txt:188`

## Practical Mapping: Lifecycle -> Memos

- Realm bootstrap and trust root:
`0002`, `0024`, `0045`
- Join/invite/delegation:
`0003`, `0023`, `0038`
- Vault operations and recovery:
`0006`, `0017`, `0030`
- Replication/federation:
`0007`, `0012`, `0054`
- Audit/monitoring:
`0005`, `0033`
