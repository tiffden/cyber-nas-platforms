# Overview of Joins

## From auto-enroll.scm:94

"Join listener state (any member can run this)"

## From auto-enroll.scm:687 — what happens immediately after a successful join

"Auto-start our own join listener (any member can accept joins)"

So the design intent is: after joining, a node automatically starts its own join listener so it can sponsor future joiners. Every enrolled node becomes a potential entry point.

## Who Needs to Listen

Only the master strictly needs to listen for the first join. After that, any member can sponsor — but if nobody is listening at all, nothing can join.
After joining, vault propagation is gossip (TCP push/pull between known peers via memo-0012), not the join listener. The join listener is purely membership admission. So a non-sponsoring node has no reason to keep it open.
mDNS is discovery-only — it announces where the join listener is. Not involved in vault propagation at all.

## UI Issue

The actual gap in the UI harness:

--start-realm exits → nobody listening → join-all would fail with "Could not connect to master." The Chicken code auto-starts a listener after a join completes, but the Chez harness never gets there because there's nothing to join to yet.

The minimal fix for the demo:

Machine 1 needs to keep a join listener open after --start-realm until all expected nodes have joined. After that it can do whatever.

That's not a daemon — it's a bounded wait.

The Chicken implementation already has this shape (listener runs, joiners arrive, listener stays up as long as the process lives). The harness just needs --start-realm to not exit immediately.
