# Phase 13 stage 1 verification log, 2026-08-21

Working notes. Raw material for the stage 3 issue, which has to carry every
measurement with its date and the verification list with its actual results.

Account `sj1136`, laptop macOS, cluster `amarel-new.hpc.rutgers.edu`
(login nodes amarel3 / amarel4).

## What was installed

| Path | SHA-256 |
|---|---|
| cluster `~/bin/amarel-dev-lib` | `604970fc6b84bf73fec378eac55e7dc6e87d035a7b6303cb786685b21ed51cf6` |
| cluster `~/bin/dev-session` | `4286da0d480cd810e4445cc80613bd4a7635084a4eb3591b17b5e7fa5885cef5` |
| cluster `~/bin/amarel-dev-connect` | `46326e33b41f9e672729541add49f4f3dad148b02903e40fbd3caeefc56441b6` |
| cluster `~/.amarel-dev.conf` | mode 600, partition p_wj183_1, 4 cores, 16G, 3-00:00:00 |
| cluster `~/.bash_profile` | lines 18-88 replaced by the marked block |
| laptop `~/.ssh/config` | `amarel-dev` ProxyCommand rewired |

All three checksums match the committed files as of the stage 2 comment fixes.
Re-installed and re-verified after that change: selftest OK, status RUNNING on
gpuk008, warm connect 0.34s.

Backups kept: cluster `~/.bash_profile.bak-phase13-20260821-104606`,
`~/bin/dev-session.bak-phase13-20260821-102448`, laptop
`~/.ssh/config.bak-phase13-20260821-102446` and
`~/.ssh/config.bak-phase13-step3-*`.

Migration item 0c, the job that was running before any of this:
`60690397`, 4 cores on gpuk012, 21:53:25 elapsed, 2-02:06:35 left.

## The ssh_config change

One line, plus its comment:

```
-  ProxyCommand /Users/sj1136/bin/amarel-dev-proxy
+  ProxyCommand ssh -q amarel-jump bin/amarel-dev-connect
```

`amarel-jump` already matched the plan's spec and was left alone. The
`ControlMaster` / `ControlPath` / `ControlPersist` / `ServerAliveInterval 15` /
`ServerAliveCountMax 3` lines on `amarel-dev` were already correct and were
left alone. `~/.ssh/cm/` exists; the socket path is 22 bytes against the macOS
104 byte cap.

## Cluster facts, re-read today

```
sacctmgr assoc for sj1136     accounts guest and general
sbatch --test-only            p_wj183_1 starts 10:45:12 on gpuk008   (lab, accessible)
                              main      starts 10:46:12 on hal0198
                              nonpre    starts 13:09:12 on hal0125
                              cmain     starts 10:45:12 on halc010
sinfo MaxTime                 main 259200s, graphical 86400s, p_wj183_1 1209600s
reservations                  maintenance-202609/10/11/12, all Flags=MAINT, 663 nodes
                              2026-workshop-sept, 2026-workshop-nov, oarc-tech/issues/65
next MAINT window             2026-09-15 08:00 to 2026-09-16 23:59
```

The MAINT trap, confirmed live: `scontrol show res -o | grep -c State=ACTIVE`
returns 1 today, because `oarc-tech/issues/65` runs to 2027-07-31. A check on
"is any reservation active" would refuse every connection for eleven months.
`adl_maint_open` returns not-open.

## Verification results

Numbering follows the plan.

| # | Item | Result |
|---|---|---|
| 1 | `setup.sh` Phase 13 writes both blocks | PASS. Both blocks written by setup.sh, warm connect 0.61s to gpuk008, re-run skipped every phase |
| 2 | `ssh amarel-dev hostname` returns a compute node | PASS. gpuk012, then gpuk008, never amarel3/4 |
| 3 | Cold path provisions unaided | PASS. CLI 6.7s, and a deliberate Remote Window click landed on gpuk008 at 10:59 |
| 4 | Stale master | PASS. Broken pipe, fallback, new job, 10.5s |
| 5 | Dirty shell refusal | PASS, with a correction. See below |
| 6 | Maintenance refusal | PENDING, needs the 2026-09-15 window |
| 7 | Trim path | PENDING, needs the collision zone from 2026-09-12 |
| 8 | Generic partition | PASS. main, hal0198, TIME_LIMIT 3-00:00:00 from sinfo |
| 9 | Source Control on a compute node | PASS in part. git 2.55.0 resolves and runs on gpuk008 |
| 10 | Session length question | PENDING. Both lanes are written; neither has been exercised, because ~/.amarel-dev.conf already exists and is deliberately preserved |
| 11 | Windows | DEFERRED by the user on 2026-08-21, after the macOS path is finished |
| 12 | Where the stderr line appears | PENDING, needs 2026-09-15 |
| 13 | Reset removes everything | PARTIAL. Logic verified offline; not run against the live account |

### Timings

```
warm, job already running        0.36s  -> gpuk012
cold, queue empty                6.75s  -> gpuk008, job 60724747 provisioned
cold, after full job teardown   10.47s  -> gpuk008, job 60724755, stale master broke first
editor's own reconnect          ~3s     -> gpuk008, job 60724744, no human action
```

The Remote Window click itself, run by the user at 10:59 on 2026-08-21,
landed on gpuk008. That closes item 3 and the plan's success criterion for the
macOS path.

The editor-reconnect line matters too: job `60690397` was force-stopped at 10:47 and the editor
reconnected through the new `amarel-dev-connect` and provisioned `60724744`
within three seconds, with nobody clicking anything. That is lane 1 working
end to end through the repo version, and it repeats the 2026-08-21 prototype
measurement (cancel 12:36:15, submitted 12:36:20, RUNNING 12:36:21).

### Jobs created and destroyed today

```
60690397  pre-existing, gpuk012, p_wj183_1  force-stopped for the cold-path test
60724744  gpuk008   provisioned by the editor's own reconnect
60724747  gpuk008   provisioned by a CLI cold connect, 6.7s
60724755  gpuk008   provisioned after a stale master cleared, 10.5s
60724761  hal0198   general-partition test on main, TIME_LIMIT 3-00:00:00
60724845  gpuk008   the session now running, p_wj183_1, 3 days
```

### Guards

```
hard gate      ssh amarel-jump true | wc -c   ->  0 bytes, before and after the .bash_profile swap
login guard    ssh -T amarel-jump 'bash --login -c "echo SHOULD-NOT-REACH-HERE"'
               ->  REFUSED: this is an Amarel login node.
                   Editor remote-servers must run on a compute node...
               The marker string never printed.
interactive    ssh -t amarel-jump 'echo INTERACTIVE-OK'  ->  INTERACTIVE-OK
stop guard 1   dev-session stop with 1 window attached
               ->  refusing to stop job 60690397, 1 editor window(s) still attached on gpuk012
                   exit 1, job survived
stop --force   cancelled job 60690397
cpu probe      adl_cpu_delta_ms on an idle job  ->  2ms over 3s, threshold 200
               matches the 2026-08-20 measurement of 2.6ms over 10s
windows probe  adl_windows  ->  1 and 2 at different points, tracking real attachment
```

### Clamp behaviour

```
3d on main         -> 3-00:00:00 |
3d on graphical    -> 1-00:00:00 | the graphical partition MaxTime
3d on p_wj183_1    -> 3-00:00:00 |
30d on main        -> 3-00:00:00 | the main partition MaxTime
4h on main         -> 0-04:00:00 |
3d, window 10h out -> 0-09:00:00 | the next maintenance window     (simulated)
3d, window 30m out -> 0-01:00:00 | the one hour minimum            (simulated)
```

### Unit tests

All six SLURM time forms, both dashed and dashless. Conf parsing accepts a good
file and rejects `main; rm -rf /`, `-4`, `lots`, `4h` and `../escape`, falling
back to defaults with a warning each.

**Correction.** An earlier version of this log said `shellcheck -S warning` was
clean on all three scripts. It was not: there were nine SC2034 findings across
the three (four in the lib, three in connect, two in dev-session), all of them
false positives. They are now actually resolved rather than merely claimed:
unused loop counters became `for _ in`, the discarded half of the clamp read
became `_`, three stale `local` declarations were dropped, and the lib carries
one targeted `# shellcheck disable=SC2034` because shellcheck cannot see that a
sourcing script consumes those settings. `shellcheck -x -S warning` now reports
clean on each file individually.

## Defects found and fixed while testing

1. `adl_clamp_walltime` set `ADL_CLAMP_REASON`, but every caller used it as
   `spec=$(...)`, so the assignment died in the subshell and no user would ever
   have been told which clamp applied. Now prints `SPEC|REASON`.
2. `adl_tl_seconds` applied the dashless rule after a dash. SLURM reads `1-12`
   as one day twelve hours and bare `12` as twelve minutes, so `1-12` parsed as
   1d 12m, an 11.8 hour shortfall on a value the conf validator accepts. The
   prototype had this wrong in all three copies.
3. The selftest printed the next maintenance date twice, from a
   `${m:+...}${m:-...}` pair that both expand when `m` is set.

4. Three comments, and this log, overstated what stray stdout does to the
   tunnel. See the item 5 finding below. Corrected in `amarel-dev-lib`,
   `amarel-dev-connect`, `setup.sh`, `SKILL.md` and `AGENTS.md`.

## Item 5, the dirty shell refusal, and what it actually proved

Tested by appending `echo NOISE-TEST-PHASE13` to the cluster `~/.bashrc`, then
restoring it from the backup taken in the same command.

```
gate probe   ssh <host> true | wc -c    ->  19        the gate fires correctly
what it saw  NOISE-TEST-PHASE13
tunnel       ssh amarel-dev hostname -s ->  gpuk008   IT STILL CONNECTED
after restore  gate probe 0 bytes, connect gpuk008
```

The gate works. The stated reason for it did not survive the test. Three code
comments claimed that any byte on stdout corrupts the handshake, and it does
not: RFC 4253 section 4.2 says the server "MAY send other lines of data before
sending the version string" and "Clients MUST be able to process such lines".
A whole line before the SSH identification string is therefore legal and was
tolerated, with the noise printed above the result.

What is still not tolerated: output after the banner, a partial line, and any
line beginning with `SSH-`, which the RFC forbids. The gate stays a refusal
rather than a warning, because the difference is not worth betting a connection
on and the noise is printed to the user on every single connect. The comments
now say that instead of the overstatement.

## Item 13, what was and was not tested

The reset was not run against the live account: a `full` reset deletes the key
pair and the working session, and that is the user's call rather than mine.
What was verified offline:

```
awk on the real ~/.ssh/config   all three amarel blocks and their comment runs
                                removed; the user's own Host rutgers.edu intact
awk on a synthetic edge case    stanzas either side of the removed block intact
PowerShell twin                 no PowerShell on this machine. Logic ported to
                                python and diffed against the awk on both
                                files: identical output. Syntax unverified
bash_profile marker deletion    tested against the real markers at lines 1 and
                                71 of cluster/bash_profile_block.sh
extracted reset.sh              bash -n clean, shellcheck -S warning clean
```

## Still live on the laptop, deliberately

`~/bin/amarel-dev-proxy` and `~/bin/amarel-maint` are now dead code: nothing
references them. They stay until stage 2 ships and passes, per the plan's
migration section, then they go so there is one version to maintain.
