# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A one-click Docker Compose environment that spins up an interactive CTF for one
IT intern. The intern SSHes into a "hub" container whose login shell is a
React Ink TUI; the TUI walks them through 10 sequential tasks targeted at
other containers on the same Docker network. Each spin-up regenerates all
answers.

## Common commands

```bash
./spin-up.sh                      # generate flags, build, start, print mentor password
./spin-up.sh --fresh              # also regenerate secrets when hub.env already exists
./tear-down.sh -y                 # stop + wipe volumes + clear secrets/
./tear-down.sh -y --keep-state    # preserve intern progress volume
./smoke-test.sh                   # end-to-end check (runs on host, exits non-zero on failure)

ssh -t intern@localhost -p 2222   # intern entrypoint; password: ctf
```

Inside the hub:

```bash
ctf-verify task04 "<answer>"      # used by the Ink app; setuid exit 0/1
ctf-reveal                        # mentor-password-gated answer dump
node /opt/ctf-hub/dist/index.js --self-check
```

Ink app dev loop (only when iterating on the TUI locally — not required to
run the stack):

```bash
cd hub/app
npm install
npx tsc --noEmit                  # type-check
npm run build                     # emit dist/
CTF_VERIFY_PATH=/bin/false node dist/index.js --self-check
```

## Architecture highlights

**Randomization & chaining.** `scripts/generate-flags.sh` is the single source
of randomness. It runs once per spin-up, writes `secrets/hub.env` (mode 0600,
the full flag map) plus per-task env slices, and emits the mentor password on
stdout for `spin-up.sh` to capture. Task 04's plaintext is generated first
and deliberately reused: it's the input that derives the Task 06 DNS hostname
(`h-<sha256(plaintext)[0:8]>.internal.ctf`) and the Task 08 auth token. If
you change one of these, update the others.

**Privilege separation.** The Ink app runs as unprivileged user `intern`.
`/etc/ctf/hub.env` is bind-mounted `root:root 0600`. Verification goes through
two setuid C helpers in `hub/helpers/`:

- `ctf-verify TASK_ID ANSWER` — reads `hub.env`, normalizes + constant-time
  compares, exits 0/1. Must never print the expected value and must sleep on
  failure.
- `ctf-reveal` — reads `mentor.hash` (SHA-512 crypt from `openssl passwd -6`),
  prompts for the password with termios no-echo, `crypt(3)`-compares, and on
  success prints every `FLAG_*` line from `hub.env`.

If you edit either helper, keep them standalone C with no network I/O and
compile them in stage 1 of `hub/Dockerfile` with `chmod 4755`.

**Ink TUI.** `hub/app/` is React Ink 5 (ESM-only) with TypeScript NodeNext
module resolution — imports inside `src/` must use `.js` extensions even
though the sources are `.ts`/`.tsx`. The TUI never reads `hub.env`; it always
calls `ctf-verify` via `spawnSync` in `src/verify/verify.ts`. Task metadata
(titles, descriptions, hints) lives in `src/tasks/index.ts` and **must not
contain answers**.

Drop-to-shell: `src/index.tsx` runs a loop that `render()`s `<App/>`, waits
for unmount, and — if the app signaled "drop to shell" — `spawnSync`s bash
before re-rendering. Because Ink is `intern`'s login shell, the nested bash
also runs as `intern`, so drop-to-shell is not an escalation path.

**Task container convention.** Each `tasks/taskNN-*/` has a `Dockerfile` plus
an `entrypoint.sh` that starts with `set -euo pipefail`, validates required
env vars with `: "${FLAG_TASKNN_FOO:?missing FLAG_TASKNN_FOO}"`, renders any
templated data, and `exec`s its service in the foreground. Env vars are
provided via `env_file: ./secrets/taskNN.env` in `docker-compose.yml`.

**Fixed IPs and hostnames.** `ctfnet` is `10.42.0.0/24` with hardcoded
addresses (hub 10.42.0.10, mercury .20, mars-hop .22, venus .23, earth-logs .24,
jupiter-api .25, saturn-crypto .26, neptune-final .27, decoys .30+). Task
descriptions refer to hosts by name, so changing these requires updating
`hub/app/src/tasks/index.ts` and `smoke-test.sh` in lockstep.

**State.** Single JSON at `/var/ctf/state/intern.json` on a named volume.
Atomic write via temp+rename in `hub/app/src/state/progress.ts`. No locking;
the architecture is one stack per intern.

## Things to watch when editing

- `scripts/generate-flags.sh` order matters — Task 04 plaintext must be
  generated before anything that depends on it.
- Don't put answers in TypeScript sources. Only `secrets/hub.env` knows the
  answers; the TUI asks the setuid helper.
- When adding a new task, update (in this order): `scripts/generate-flags.sh`
  (flag + env slice), `docker-compose.yml` (service + env_file), a new
  `tasks/taskNN-*/` directory, `hub/app/src/state/progress.ts` (extend
  `TaskId`), `hub/app/src/tasks/index.ts` (metadata), and `smoke-test.sh`
  (end-to-end check).
- `FLAG_TASK10_EXPECTED` is the sha256 of `FLAG_TASK01..FLAG_TASK09` joined
  with `\n`, no trailing newline. Three places encode this: the generator,
  `tasks/task10-final/entrypoint.sh`'s served `/expected.sha256`, and the
  smoke test. Keep them in sync.
- The Ink app is ESM-only. In TS sources, relative imports must end in `.js`.
