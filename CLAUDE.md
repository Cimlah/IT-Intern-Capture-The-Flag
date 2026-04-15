# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A multi-instance Docker Compose environment that spins up an interactive CTF
for one IT intern per instance. The intern SSHes into a "hub" container whose
login shell is a React Ink TUI; the TUI walks them through 10 sequential tasks
targeted at other containers on the same Docker network. Every spin-up
regenerates all answers. Multiple instances can run side-by-side on one host,
each as a separate Compose project with its own network, secrets, and host
SSH port.

## Common commands

```bash
./spin-up.sh alice                # flags → build → start → print mentor pw for instance "alice"
./spin-up.sh bob --fresh          # second instance; auto-picks the next free SSH port
./tear-down.sh alice -y           # scoped teardown (leaves other instances running)
./tear-down.sh --all -y           # nuke every instance under secrets/
./smoke-test.sh alice             # end-to-end check for one instance (host-side, non-zero on failure)

# Instance name defaults to "default" if omitted:
./spin-up.sh                      # == ./spin-up.sh default
./smoke-test.sh                   # == ./smoke-test.sh default

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
of randomness. It takes the target secrets dir as its first argument (e.g.
`scripts/generate-flags.sh secrets/alice`) and writes `<dir>/hub.env` (mode
0600, the full flag map), per-task env slices, and `<dir>/override.yml` (the
per-instance decoy containers). It emits the mentor password on stdout for
`spin-up.sh` to capture. Task 04's plaintext is generated first and
deliberately reused: it's the input that derives the Task 06 DNS hostname
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
provided via `env_file: ${CTF_SECRETS_DIR}/taskNN.env` in `docker-compose.yml`
— `CTF_SECRETS_DIR` is set by `spin-up.sh` to `secrets/<instance>` so each
Compose project reads its own flag slices.

**Multi-instance topology.** Each instance is a Compose project named
`ctf-<instance>`, with a bridge network whose subnet Docker auto-allocates
from its default address pool. Stable hostnames (`hub`, `mercury`, `mars-hop`,
`venus`, `earth-logs`, `jupiter-api`, `saturn-crypto`, `neptune-final`, and
each decoy) are declared as `networks.ctfnet.aliases` on their services;
Docker's embedded DNS registers the aliases scoped to that network, so two
instances can both have a `mercury` without conflict. There are no fixed IPs
— `hub/entrypoint.sh` resolves `venus` at boot via `getent hosts` and prepends
the result to `/etc/resolv.conf` so dig/nslookup hit the task06-dns container
first. If you change one of the stable hostnames, update
`hub/app/src/tasks/index.ts` and `smoke-test.sh` in lockstep.

**State.** Single JSON at `/var/ctf/state/intern.json` on a named volume
(`state`, automatically scoped per Compose project, so each instance has its
own copy). Atomic write via temp+rename in `hub/app/src/state/progress.ts`.

## Things to watch when editing

- `scripts/generate-flags.sh` order matters — Task 04 plaintext must be
  generated before anything that depends on it. The script takes the target
  secrets directory as its first arg; default is `secrets/default`.
- Don't put answers in TypeScript sources. Only `secrets/<instance>/hub.env`
  knows the answers; the TUI asks the setuid helper.
- When adding a new task, update (in this order): `scripts/generate-flags.sh`
  (flag + env slice — remember to write into `$SECRETS_DIR`), `docker-compose.yml`
  (service + `env_file: ${CTF_SECRETS_DIR}/taskNN.env` + `networks.ctfnet.aliases`),
  a new `tasks/taskNN-*/` directory, `hub/app/src/state/progress.ts` (extend
  `TaskId`), `hub/app/src/tasks/index.ts` (metadata), and `smoke-test.sh`
  (end-to-end check).
- `FLAG_TASK10_EXPECTED` is the sha256 of `FLAG_TASK01..FLAG_TASK09` joined
  with `\n`, no trailing newline. Three places encode this: the generator,
  `tasks/task10-final/entrypoint.sh`'s served `/expected.sha256`, and the
  smoke test. Keep them in sync.
- The Ink app is ESM-only. In TS sources, relative imports must end in `.js`.
# CTF Challenge System for IT Interns — Implementation Plan

## Context

We're building a one-click Capture-The-Flag challenge environment for IT interns, from scratch in an empty repository at `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag`. The intern SSHes into a "hub" container running a custom React Ink (TypeScript) TUI as their login shell, and works through ~10 sequential Linux / networking / programming tasks targeted at other containers in a Docker Compose network. Each challenge instance must have unique random answers, the whole experience must take ≥4 hours, and it should spin up with a single command.

**User decisions already made:**
- **Deployment model**: one docker-compose stack per intern. A mentor (or the intern) runs `./spin-up.sh` to get a fresh environment with fresh flags.
- **Task 04 (base64)**: honor system — intern is instructed to write their own decoder and save it to `~/solutions/task04.*` for mentor review.
- **Task chaining**: flags from earlier tasks feed later tasks (Task 04 plaintext drives Task 06 DNS name and Task 08 auth token). One random seed, narrative cohesion.
- **Answer file protection**: intern user must NOT be able to `cat` the answer file. Answers are only revealable via a `ctf-reveal` helper that requires a **mentor password** generated at spin-up time.

## Architecture Overview

- **Docker Compose** orchestrates a bridge network `ctfnet` (subnet `10.42.0.0/24`) containing the hub + one container per task + decoy containers.
- **Hub container**: Debian slim + Node 20 + OpenSSH + all recon/programming tools the intern will need. User `intern` has login shell `/usr/local/bin/hub-shell`, which MOTDs and `exec`s the Ink app.
- **Ink app**: the intern's only UI. Shows task list with lock/current/done states, shows task description, collects answers via `ink-text-input`, verifies locally, persists per-intern progress JSON.
- **Privileged verification**: the Ink app (running as `intern`) cannot read the plaintext answers file. All verification goes through a setuid C helper `ctf-verify` that reads `/etc/ctf/hub.env` (root:root 0600) and returns exit 0/1. A second setuid helper `ctf-reveal` prompts for the mentor password and prints the answers if correct.
- **Task containers**: minimal Alpine images with an `entrypoint.sh` that reads env vars into templated config files (via `envsubst`) and starts its service.
- **Randomization**: `scripts/generate-flags.sh` runs at spin-up, writes per-service env files under `secrets/`, and Compose hydrates containers from them. The mentor password is generated here and printed to the operator's terminal exactly once.
- **State**: one-instance-per-intern means a single JSON file at `/var/ctf/state/intern.json` on a named volume. No locking, no multi-user complexity.

## Directory Layout

```
IT-Intern-Capture-The-Flag/
├── README.md                      # Usage: spin-up, connect, teardown
├── CLAUDE.md                      # Already exists — update with commands after skeleton lands
├── docker-compose.yml
├── .env.example                   # CTF_SSH_PORT, CTF_MENTOR_PASSWORD (optional override)
├── .gitignore                     # secrets/, state/, *.env (except .env.example)
├── spin-up.sh
├── tear-down.sh
├── smoke-test.sh
│
├── secrets/                       # gitignored; created by spin-up.sh
│   ├── hub.env                    # root:root 0600 inside container; full answer map
│   ├── mentor.hash                # bcrypt hash of mentor password
│   ├── task02.env ... task10.env  # per-service slices
│
├── scripts/
│   ├── lib/
│   │   ├── random.sh              # rand_hex, rand_word, rand_port, rand_pronounceable
│   │   └── wordlist.txt           # ~200 pronounceable words for human-friendly flags
│   └── generate-flags.sh
│
├── hub/
│   ├── Dockerfile                 # multi-stage: builder for Ink app + C helper, final runtime
│   ├── sshd_config
│   ├── entrypoint.sh              # host keys, sshd -D
│   ├── motd
│   ├── bin/
│   │   ├── hub-shell              # login shell wrapper → exec node dist/index.js
│   │   └── drop-to-shell          # helper invoked by Ink "drop to shell" action
│   ├── helpers/                   # compiled during build
│   │   ├── ctf-verify.c           # setuid: verifies (task_id, answer) against hub.env
│   │   └── ctf-reveal.c           # setuid: mentor-password-gated answer printer
│   └── app/                       # React Ink TypeScript app
│       ├── package.json
│       ├── tsconfig.json
│       └── src/
│           ├── index.tsx
│           ├── App.tsx
│           ├── components/{Header,TaskList,TaskDetail,AnswerInput,Feedback,HelpBar}.tsx
│           ├── state/{store,progress}.ts
│           ├── tasks/{index,task01..task10}.ts
│           ├── verify/verify.ts   # shells out to ctf-verify
│           └── util/{shellOut,logger}.ts
│
└── tasks/
    ├── task02-portscan/           # also serves task 03's HTTP response
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   └── www/
    ├── task05-ssh-hop/
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   └── sshd_config
    ├── task06-dns/
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   └── zones/db.internal.ctf.template
    ├── task07-logs/
    │   ├── Dockerfile
    │   └── entrypoint.sh          # generates synthetic access.log on boot
    ├── task08-api/
    │   ├── Dockerfile
    │   ├── entrypoint.sh
    │   └── app.py                 # tiny Flask or http.server
    ├── task09-crypto/
    │   ├── Dockerfile
    │   └── entrypoint.sh          # generates ct + key at boot
    └── task10-final/
        ├── Dockerfile
        └── entrypoint.sh          # serves /expected.sha256
```

Note: tasks 01 (network scan) and 04 (base64 decode) do **not** need dedicated containers. Task 01 scans the existing task containers + decoys. Task 04 is pure client-side work on the hub.

## Docker Compose Topology

- **Network**: single bridge `ctfnet` with subnet `10.42.0.0/24`. Fixed IPs per service so task descriptions can refer to stable hostnames.
- **Services**:
  - `hub` (10.42.0.10) — ports `${CTF_SSH_PORT:-2222}:22`, mounts `secrets/hub.env` → `/etc/ctf/hub.env:ro`, mounts `secrets/mentor.hash` → `/etc/ctf/mentor.hash:ro`, mounts named volume `state:/var/ctf/state`, `env_file: secrets/hub.env` (for bootstrap only — the Ink app reads the file directly via the helper).
  - `task02-portscan` (10.42.0.20, hostname `canary`) — HTTP server on randomized port; also hosts Task 05's `hop.txt`.
  - `task05-ssh-hop` (10.42.0.22, hostname `robin-hop`) — OpenSSH with `pivot` user + randomized password, `/home/pivot/flag.txt` with the Task 05 flag.
  - `task06-dns` (10.42.0.23, hostname `nsd`) — dnsmasq serving `internal.ctf` zone.
  - `task07-logs` (10.42.0.24, hostname `owl-logs`) — busybox httpd serving generated access.log.
  - `task08-api` (10.42.0.25, hostname `finch-api`) — Python micro-API.
  - `task09-crypto` (10.42.0.26, hostname `wren-crypto`) — busybox httpd serving generated cipher + key.
  - `task10-final` (10.42.0.27, hostname `raven-final`) — busybox httpd serving `expected.sha256`.
  - `decoy-1` ... `decoy-N` (10.42.0.30+) — alpine `sleep infinity` containers with randomized hostnames picked from a bird-name list. Number of decoys is also randomized (3–5).
- **Volumes**: named volume `state` for intern progress JSON.
- **DNS**: the hub's resolv.conf is appended with `nameserver 10.42.0.23` at hub entrypoint, so `dig TXT foo.internal.ctf` reaches Task 06's dnsmasq.

## Randomization & Secrets Flow

`scripts/generate-flags.sh` produces all random values in one pass. Ordering matters because of chaining:

1. Generate `FLAG_TASK04_PLAINTEXT` first (e.g. `foobar-9342`, pronounceable word + digits via `wordlist.txt`).
2. Derive `FLAG_TASK03_B64 = base64(FLAG_TASK04_PLAINTEXT)`.
3. Derive `FLAG_TASK06_HOST = "h-" + sha256(FLAG_TASK04_PLAINTEXT)[0:8] + ".internal.ctf"`.
4. Derive `FLAG_TASK08_AUTH_TOKEN = FLAG_TASK04_PLAINTEXT` (re-used as API auth header value).
5. Independently generate: `FLAG_TASK02_PORT` (1024–65000, avoiding 2222), `FLAG_TASK05_SSH_PASS` (triple-word), `FLAG_TASK05_FILE` (hex), `FLAG_TASK06_TXT` (hex), `FLAG_TASK07_TX` (e.g. `TX-8d3f91`), `FLAG_TASK08_SECRET` (hex), `FLAG_TASK09_PLAINTEXT` (short pronounceable sentence), decoy hostnames list.
6. Task 01 answer: sorted, lowercase, comma-joined list of non-decoy hostnames on `ctfnet`. Because task container names are fixed, this value is fixed across instances — but the **decoy set** is randomized, so the distinguishing answer ("which are the targets") varies meaningfully per instance.
7. Task 09: `FLAG_TASK09_CIPHERTEXT` + `FLAG_TASK09_KEY` computed from plaintext + `openssl rand`.
8. Task 10: `FLAG_TASK10_EXPECTED = sha256(FLAG_TASK01 + "\n" + ... + "\n" + FLAG_TASK09)`.

**Mentor password** (new, from user's Q4 answer):
- If `CTF_MENTOR_PASSWORD` is set in env, use it. Otherwise generate a random triple-word password.
- Compute `bcrypt(password)` using a tiny helper (Python `bcrypt` one-liner, or `openssl passwd -6` if we accept SHA-512 instead — SHA-512 crypt via `openssl passwd -6` needs no extra dependencies).
- Write hash to `secrets/mentor.hash`.
- Print the plaintext mentor password to the operator's terminal **exactly once** at end of `spin-up.sh`, with a warning to save it. Never persist plaintext to disk.

**Files produced** under `secrets/`:
- `hub.env` — full map, chmod 0600. Mounted into the hub container as `/etc/ctf/hub.env` read-only, owned by root:root inside container. The helper binaries read it; the Ink app (running as `intern`) cannot.
- `mentor.hash` — bcrypt/SHA-512 hash, mode 0644 in container. The `ctf-reveal` helper reads it.
- `task02.env`, `task05.env`, ..., `task10.env` — per-service slices. Each Compose service loads only its own via `env_file`. Keeps blast radius narrow.

**Why env files instead of Docker secrets**: simpler, work naturally with Compose `env_file:`, don't require swarm mode, and the threat model is a teaching env (not prod).

## Hub Container Design

**Base**: `node:20-bookworm-slim`. Multi-stage build:
- **Stage 1 (builder)**: install `build-essential`, compile `ctf-verify.c` and `ctf-reveal.c` from `helpers/`. `npm ci` + `npm run build` the Ink app.
- **Stage 2 (runtime)**: apt install `openssh-server nmap curl wget netcat-openbsd dnsutils python3 python3-pip jq xxd openssl tcpdump iproute2 iputils-ping nano vim-tiny less grep gawk sed findutils file tree gettext-base tmux ca-certificates libcrypt1`. Copy compiled helpers from stage 1 with `chmod u+s`. Copy Ink `dist/` from stage 1.

**User setup**:
- `useradd -m -s /usr/local/bin/hub-shell intern`
- `echo 'intern:ctf' | chpasswd` (fixed SSH password; this isn't the challenge)
- `chown root:root /etc/ctf/hub.env && chmod 0600 /etc/ctf/hub.env` (applied by entrypoint, since the file is bind-mounted)

**sshd_config**: `PermitRootLogin no`, `PasswordAuthentication yes`, `AllowUsers intern`, no `ForceCommand` (we rely on the login shell).

**`/usr/local/bin/hub-shell`** (bash):
```bash
#!/usr/bin/env bash
set -euo pipefail
# Require a TTY; if missing, tell user to reconnect with -t
if [ ! -t 0 ] || [ ! -t 1 ]; then
  echo "This challenge requires a PTY. Reconnect with: ssh -t intern@..."
  exit 1
fi
cat /etc/ctf/motd 2>/dev/null || true
exec /usr/bin/node /opt/ctf-hub/dist/index.js "$@"
```

**Setuid helpers** (20–40 lines of C each; compiled at image build):
- `ctf-verify TASK_ID ANSWER` — opens `/etc/ctf/hub.env`, finds `FLAG_<TASK_ID>=...`, normalizes both sides (lowercase, trim), compares, exits 0/1. Must not print the expected value on failure. No side channels.
- `ctf-reveal` — prompts `Mentor password: ` (no-echo via termios), reads stdin, computes hash (same scheme as `mentor.hash`), compares. On match: prints all `FLAG_*` entries. On mismatch: exits 1. Rate-limit via a sleep on failure.

**Ink app structure**:
- **State** (`state/store.ts`): `{ statuses: Record<TaskId, 'locked' | 'current' | 'completed'>, attempts: Record<TaskId, number>, completedAt: Record<TaskId, string>, startedAt: string }`.
- **Persistence** (`state/progress.ts`): JSON at `/var/ctf/state/intern.json`. Atomic write (temp + rename). Load on start; if missing, init with task01 current.
- **Task definitions** (`tasks/taskNN.ts`): `{ id, title, description, hints[], estimatedMinutes }`. **No answers in TypeScript.**
- **Verification** (`verify/verify.ts`): `verify(taskId, input)` → `spawnSync('/usr/local/bin/ctf-verify', [taskId, input])` → `status === 0`. Never reads `hub.env` directly.
- **Drop to shell**: Ink "d" key → `ink.unmount()` → `spawnSync('/bin/bash', ['--login'], { stdio: 'inherit' })` → on bash exit, `render(<App/>)` again. Because Ink is the login shell running as `intern`, the nested bash also runs as `intern` — intern cannot escalate.
- **Components**: `Header` (hub + elapsed time), `TaskList` (left pane with status icons), `TaskDetail` (right pane: title, description, attempts, est. time), `AnswerInput` (bottom modal; `ink-text-input`), `Feedback` (success/failure banner), `HelpBar` (↑↓ navigate, Enter select, a answer, h hint, d drop-to-shell, q quit).
- **Locked tasks**: title + position visible; description hidden. Gives the intern a sense of total length without spoiling the content.

## Task Containers

Each task container is a 5–30 line Dockerfile + an `entrypoint.sh` that:
1. Validates required env vars are set (`: "${FLAG_TASKXX_YYY:?}"`).
2. Renders any templated config (`envsubst < template > rendered`).
3. Execs the service in the foreground.

Examples:
- **task02-portscan/entrypoint.sh**: decodes `FLAG_TASK03_B64` or reuses `FLAG_TASK04_PLAINTEXT` to write `/srv/www/index.html` (base64-encoded) and `/srv/www/hop.txt` (Task 05 SSH password), then `exec busybox httpd -f -p "$FLAG_TASK02_PORT" -h /srv/www`.
- **task05-ssh-hop/entrypoint.sh**: creates `pivot` user, sets password from `FLAG_TASK05_SSH_PASS`, writes `/home/pivot/flag.txt = FLAG_TASK05_FILE`, generates host keys, execs sshd.
- **task06-dns/entrypoint.sh**: renders dnsmasq hosts file from template using `FLAG_TASK06_HOST` → ARbitrary IP + a TXT record `FLAG_TASK06_TXT`, execs dnsmasq in foreground.

## Full Task List (≥4 hours)

Times target a comfortable-with-CLI intern who's new to pen-testing basics. Total: 240 min budget baseline; realistic friction takes most interns to 4.5–5h.

1. **Task 01 — Reconnaissance: Network Scan** *(15 min)*
   - **Title**: "Who's on the wire?"
   - **Description**: "You've landed on the hub. Somewhere on this network there are other hosts — some are targets, some are decoys. Find all live hosts on the network. The targets are named after songbirds you'll need to probe in later tasks; decoys are named after other birds. Submit a comma-separated, sorted list of the target hostnames."
   - **Answer**: sorted CSV of non-decoy hostnames.
   - **Tools**: `ip addr`, `nmap -sn 10.42.0.0/24`, reverse DNS.

2. **Task 02 — Port Scan** *(15 min)*
   - **Title**: "Find the hidden door"
   - **Description**: "Host `canary` runs an HTTP server on a non-standard port. Scan it and submit the port number."
   - **Answer**: `FLAG_TASK02_PORT` (1024–65000).
   - **Tools**: `nmap -p- canary`, `nc -zv`.

3. **Task 03 — HTTP Probe** *(10 min)*
   - **Title**: "What did it say?"
   - **Description**: "GET `http://canary:<port>/` and submit the base64 string the server returns. Paste it verbatim."
   - **Answer**: `FLAG_TASK03_B64` (= base64 of Task 04 plaintext).
   - **Tools**: `curl`, `wget`.

4. **Task 04 — Decode** *(20 min)*
   - **Title**: "Crack the shell"
   - **Description**: "Write your own script (Python, Node, bash — your choice) to decode the base64 string from Task 03 and submit the decoded plaintext. Save your script to `~/solutions/task04.*` — your mentor will review it. Using `base64 -d` skips the point of the exercise."
   - **Answer**: `FLAG_TASK04_PLAINTEXT` (e.g. `foobar-9342`).
   - **Tools**: `python3`, `node`, `bash`, `xxd`.

5. **Task 05 — SSH Pivot** *(25 min)*
   - **Title**: "Jump to the next box"
   - **Description**: "On host `robin-hop` there's an account named `pivot`. Its password is hidden on `canary` at path `/hop.txt`. Retrieve the password, SSH to `robin-hop` as `pivot`, read `/home/pivot/flag.txt`, and submit its contents."
   - **Answer**: `FLAG_TASK05_FILE`.
   - **Tools**: `curl`, `ssh`, `cat`.

6. **Task 06 — DNS Detective** *(25 min)*
   - **Title**: "What's in a name?"
   - **Description**: "There's an internal DNS zone at `internal.ctf`. The hostname you need is derived from your Task 04 plaintext: take `sha256(plaintext)`, use the first 8 hex characters, and build `h-XXXXXXXX.internal.ctf`. Query its TXT record. Submit the value."
   - **Answer**: `FLAG_TASK06_TXT`.
   - **Tools**: `sha256sum`, `dig`, `nslookup`.

7. **Task 07 — Log Forensics** *(25 min)*
   - **Title**: "Needle in a haystack"
   - **Description**: "Host `owl-logs` serves an Apache access log at `http://owl-logs/access.log`. Exactly one request returned HTTP 500 and contains a transaction ID prefixed `TX-`. Find it. Submit the transaction ID."
   - **Answer**: `FLAG_TASK07_TX`.
   - **Tools**: `curl`, `grep`, `awk`.

8. **Task 08 — REST API** *(30 min)*
   - **Title**: "The API is the map"
   - **Description**: "Host `finch-api` serves a tiny JSON API on port 8080. `GET /` lists routes. One endpoint requires an `X-Auth-Token` header; the token is your Task 04 plaintext. Authenticate, find the endpoint that returns a `secret` field, submit the secret."
   - **Answer**: `FLAG_TASK08_SECRET`.
   - **Tools**: `curl`, `jq`.

9. **Task 09 — XOR Crypto** *(35 min)*
   - **Title**: "One-time what?"
   - **Description**: "`wren-crypto` serves two hex-encoded files: `/ct` (ciphertext) and `/key` (key). They're the same length. XOR them and submit the ASCII plaintext."
   - **Answer**: `FLAG_TASK09_PLAINTEXT`.
   - **Tools**: `curl`, `python3`, `xxd`.

10. **Task 10 — Grand Finale** *(40 min)*
    - **Title**: "Prove it"
    - **Description**: "Write a program (any language) that takes all 9 previous flags in order, joins them with `\n`, computes the sha256, and submits the lowercase hex digest here. Host `raven-final` exposes the expected hash at `/expected.sha256` so you can sanity-check your program."
    - **Answer**: `FLAG_TASK10_EXPECTED`.
    - **Tools**: `python3` / `sha256sum`, `curl`.

**Budget**: 15+15+10+20+25+25+25+30+35+40 = **240 min = 4.0 h** baseline.

## State & Progression

- Single JSON file `/var/ctf/state/intern.json` on named volume `state`.
- `TaskList` only shows unlock icons through the current task; later tasks render as `[ ] Task N` with no description.
- Invariant: exactly one task is `current`; on completion, next becomes `current`, current becomes `completed`. After task10 completes, app shows a "Challenge complete" screen with elapsed time and attempt stats.
- Admin reset: hidden behind env flag `CTF_ALLOW_RESET=1`, bound to a key in `HelpBar`.

## Spin-up / Tear-down / Smoke Test

**`spin-up.sh`**:
1. `set -euo pipefail`; check `docker` + `docker compose` plugin exist.
2. If `secrets/` exists and `--fresh` not passed, warn and reuse. Otherwise regenerate.
3. Run `scripts/generate-flags.sh` → populates `secrets/`. Captures generated mentor password.
4. `docker compose build`.
5. `docker compose up -d`.
6. Poll `docker compose ps` until all services are `running` (timeout 60s).
7. Print connection info + mentor password **exactly once**:
   ```
   === CTF instance ready ===
   SSH: ssh -t intern@localhost -p 2222
   Pass: ctf
   Mentor password (save now — will not be shown again): <pw>
   ```
8. Optionally run `smoke-test.sh --quick`.

**`tear-down.sh`**: `docker compose down -v` (removes containers + state volume by default), prompts before deleting `secrets/` unless `--yes`. `--keep-state` flag preserves the state volume for debug.

**`smoke-test.sh`** (runs from host, exits non-zero on failure):
- All services running (`docker compose ps --format json`).
- Hub sshd listening (`docker compose exec hub nc -zv localhost 22`).
- All task container hostnames resolvable from hub (`getent hosts`).
- HTTP probe on `canary:$FLAG_TASK02_PORT` returns `$FLAG_TASK03_B64`.
- DNS TXT query for `$FLAG_TASK06_HOST` returns `$FLAG_TASK06_TXT` via `dig @10.42.0.23`.
- SSH hop: `sshpass -p "$FLAG_TASK05_SSH_PASS" ssh pivot@robin-hop cat /home/pivot/flag.txt` matches `$FLAG_TASK05_FILE`.
- API: `curl -H "X-Auth-Token: $FLAG_TASK04_PLAINTEXT" finch-api:8080/...` returns `$FLAG_TASK08_SECRET`.
- Crypto: fetch ct + key, XOR locally in python one-liner, compare to `$FLAG_TASK09_PLAINTEXT`.
- Final: `curl raven-final/expected.sha256` equals host-computed sha256 of concatenated flags.
- Ink self-check: `docker compose exec hub node /opt/ctf-hub/dist/index.js --self-check` → exits 0 (loads task registry, pings `ctf-verify` with a known-bad input, expects non-zero exit).
- Helper check: `docker compose exec -u intern hub cat /etc/ctf/hub.env` → expected to **fail** (permission denied). Asserts privilege separation.

## Critical Files to Create (in order of implementation)

1. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/docker-compose.yml`
2. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/spin-up.sh`
3. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/scripts/generate-flags.sh`
4. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/scripts/lib/random.sh`
5. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/Dockerfile`
6. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/entrypoint.sh`
7. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/sshd_config`
8. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/bin/hub-shell`
9. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/helpers/ctf-verify.c`
10. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/helpers/ctf-reveal.c`
11. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/hub/app/src/index.tsx` + `App.tsx` + `components/*` + `tasks/*` + `verify/verify.ts`
12. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task02-portscan/*` (also carries Task 03 data and Task 05's hop.txt)
13. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task05-ssh-hop/*`
14. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task06-dns/*`
15. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task07-logs/*`
16. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task08-api/*`
17. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task09-crypto/*`
18. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/tasks/task10-final/*`
19. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/smoke-test.sh`
20. `/Users/michalstolarczyk/Documents/git/IT-Intern-Capture-The-Flag/README.md` + update `CLAUDE.md`

## Implementation Sequencing

Vertical-slice first so we catch integration issues early:

1. **Skeleton** — top-level layout, `.gitignore`, stub `docker-compose.yml` with hub only, stub `spin-up.sh`.
2. **Hub base image** — Dockerfile + sshd config; verify `ssh -t intern@localhost -p 2222` lands in `/bin/bash`.
3. **Helpers** — `ctf-verify.c`, `ctf-reveal.c` compiled setuid; hand-craft a `hub.env`; verify helpers work as root-only readers.
4. **Ink hello-world** — minimal TUI, tsc build, swap login shell to `hub-shell`. Verify Ink renders over SSH.
5. **Flag generation** — `scripts/generate-flags.sh` + integration into `spin-up.sh`. Mentor password generation + one-time print.
6. **Ink verification plumbing** — task04 (pure client-side) end-to-end: submit, verify via helper, persist state, unlock next.
7. **Task containers 02 → 03 → 05 → 06 → 07 → 08 → 09 → 10 → 01** — incrementally. Add one service + its description + smoke-test coverage per PR.
8. **Polish** — MOTD, help bar, hints (show after N failed attempts), reset flow, README.
9. **End-to-end run-through** — simulate an intern full-walkthrough; tune descriptions, time estimates.

## Verification (end-to-end)

After implementation:
1. `./tear-down.sh --yes && ./spin-up.sh --fresh` → fresh instance, mentor password printed.
2. `./smoke-test.sh` → all green in <30s.
3. Manual: `ssh -t intern@localhost -p 2222` (password `ctf`) → Ink loads, task01 unlocked, task02..10 locked and showing titles only.
4. Manual: `docker compose exec -u intern hub cat /etc/ctf/hub.env` → permission denied (privilege separation works).
5. Manual: inside Ink, "d" drops to shell, `whoami` says `intern`, `cat /etc/ctf/hub.env` denied. Exit bash returns to Ink.
6. Manual: from bash, `ctf-reveal` prompts for password, correct password prints answers, wrong password exits 1.
7. Manual: walk all 10 tasks end-to-end using a second terminal with the revealed answers, completing each in <2 min (correctness check, not time check).
8. Manual: complete task10, verify "Challenge complete" screen.
9. Repeat steps 1–3 twice and confirm all flags are different across spin-ups (randomization works).

## Risks & Open Items

- **Setuid C helpers**: tiny but must be written carefully. `ctf-verify` must not print the expected value on mismatch; must not leak via timing (string compare can be constant-time). `ctf-reveal` must use no-echo prompt, rate-limit, and compare hashes in constant time.
- **Task 01 target-name stability**: task container hostnames are fixed across spin-ups, so the literal target list is the same; only the **decoy set** varies. This weakens uniqueness-per-instance for Task 01 alone. Accepted trade-off because randomizing real service names would require regenerating compose.yml. Still effectively unique because the intern has to distinguish targets from a different decoy set each time.
- **Windows SSH clients**: the `hub-shell` wrapper checks for a TTY and prints a clear error if missing. Document `ssh -t` explicitly in README.
- **Shared-instance mode**: deferred per user's answer to Q1. Can be added later by key-ing state by OS user and provisioning per-user flag sets.
- **Task 04 enforcement**: honor system per user's answer to Q2. Mentor reviews `~/solutions/task04.*`.
- **Mentor reveal UX**: printed once at spin-up. If lost, operator runs `./spin-up.sh --reset-mentor-password` (to design — simplest: regenerate mentor.hash with new password, restart hub container only).
