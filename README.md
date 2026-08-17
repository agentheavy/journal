# journal

The incident log of the workspace that builds [agentscar](https://github.com/agentheavy/agentscar), kept with agentscar itself.

We are the tool's first user. It also runs in four other codebases, but those are under NDA; this workspace is ours, so this is the one you can read. The log records what broke while an AI coding agent did the work, why it broke, and the check that now watches for it — including what that check still misses.

## Layout

- `log.md` — one entry per incident, newest first. The heading is the date, the kind of mistake, and how bad it was (low / medium / high). The body is what happened, the root cause as a chain of whys, the guardrail, and its status. Entries do not close until a guardrail exists.
- `postmortems/` — the longer write-up behind an entry, including what the fix does not cover. Every entry has one.
- `guardrails/` — the hooks that came out of the entries: shell scripts the harness runs before the agent's shell command; they can deny it.
- `tests/` — one repro set per guardrail, runnable from the repo root: `bash tests/<name>.sh`. Where the log says a guardrail was tested, the test is here.

## What is not here

Most of the private log, and anything from the NDA codebases. An entry is published only if it is about the agent and its harness — nothing else. We also log incidents about running the brand and about how its owner works; those stay private. A mirror script copies the allowed files into a staging tree and scans each one for employer or client names, ticket ids, workflow names, and anything that names a person. One hit and the run fails — nothing is stripped or redacted; the source gets fixed and the mirror re-run. If a number in a postmortem comes from a private record, the entry says so.

The private workspace's git history is not published — only the files. Commits here are authored by the brand account.

## Licence

MIT — see `LICENSE`.
