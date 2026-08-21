# The goal the watcher measures against

Verbatim from the Phase 13 plan:

> after a one-time setup, the user opens their editor's "Open a Remote Window"
> menu, picks `amarel-dev`, and lands on a compute node. Every time, first run
> or hundredth. The only legitimate refusal is an open maintenance window.

Plus what the user asked for after that:

1. The editor never runs on a login node. That is the OARC complaint.
2. A vague failure report ("it's not working") routes into ask, fix, confirm,
   then file an issue. The skill never turns a problem away.
3. The issue is filed only after the user confirms it works, not on a machine
   check alone.
4. Session length is the user's choice, not hard-coded to the owner's 3 days.
5. Setup is one time. After that it is one click.
6. Nothing user-facing explains internals. The user gets a working thing.

Anything the watcher sees that contradicts one of these is a finding.
