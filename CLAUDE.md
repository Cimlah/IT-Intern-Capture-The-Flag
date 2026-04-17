# CLAUDE.md

Guidance for Claude Code when working with this repository.

## What this is

A multi-instance Docker Compose environment that spins up an interactive CTF
for one IT intern per instance. The intern SSHes into a `hub` container whose
login shell is a React Ink TUI; the TUI walks them through 10 sequential
tasks targeted at other containers on the same Docker network. Every
spin-up regenerates all answers. Multiple instances can run side-by-side on
one host, each as a separate Compose project with its own network, secrets,
and host SSH port.

Scope: an **internal teaching tool**, not a hardened product. Threat model
is "curious intern pokes around"; all security boundaries assume that.

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

### Randomization & chaining

`scripts/generate-flags.sh` is the single source of randomness. It takes the
target secrets dir as its first argument (e.g. `scripts/generate-flags.sh
secrets/alice`) and writes:

- `<dir>/hub.env` (mode 0600) — the full flag map
- `<dir>/taskNN.env` — per-task slices (only the vars that task needs)
- `<dir>/mentor.hash` — SHA-512 crypt of the mentor password
- `<dir>/override.yml` — per-instance decoy services for Compose
- `<dir>/decoys.env` — decoy metadata for smoke-test / debug

It emits `MENTOR_PASSWORD=<pw>` on stdout for `spin-up.sh` to capture. The
plaintext password is never written to disk.

**Task 04 plaintext is generated first and deliberately reused:**
- It's the input to `FLAG_TASK03_B64` (base64-encoded in Task 3's HTTP body).
- It derives `FLAG_TASK06_HOST = h-<sha256(plaintext)[0:8]>.internal.ctf`.
- It is `FLAG_TASK08_AUTH_TOKEN` (the `X-Auth-Token` header value).

If you change one of these rules, change them all in the generator, the
task container that materializes them, and any smoke-test assertions.

### Privilege separation

The Ink app runs as unprivileged user `intern`. `/etc/ctf/hub.env` is
bind-mounted `root:root 0600`. Verification goes through two setuid C
helpers in `hub/helpers/`:

- `ctf-verify TASK_ID ANSWER` — reads `hub.env`, normalizes + constant-time
  compares, exits 0/1. Must never print the expected value and must sleep on
  failure.
- `ctf-reveal` — reads `mentor.hash` (SHA-512 crypt from `openssl passwd -6`),
  prompts for the password with termios no-echo, `crypt(3)`-compares, and on
  success prints every `FLAG_*` line from `hub.env`.

If you edit either helper, keep them standalone C with no network I/O and
compile them in stage 1 of `hub/Dockerfile` with `chmod 4755`.

### Ink TUI

`hub/app/` is React Ink 5 (ESM-only) with TypeScript NodeNext module
resolution — **imports inside `src/` must use `.js` extensions even though
the sources are `.ts`/`.tsx`.** The TUI never reads `hub.env`; it always
calls `ctf-verify` via `spawnSync` in `src/verify/verify.ts`. Task metadata
(titles, descriptions, hints) lives in `src/tasks/index.ts` and **must not
contain answers**.

Drop-to-shell: `src/index.tsx` runs a loop that `render()`s `<App/>`, waits
for unmount, and — if the app signaled "drop to shell" — `spawnSync`s bash
before re-rendering. Because Ink is `intern`'s login shell, the nested
bash also runs as `intern`, so drop-to-shell is not an escalation path.

State file: `/var/ctf/state/intern.json` on a named volume `state`
(automatically scoped per Compose project, so each instance has its own
copy). Atomic write via temp+rename in `hub/app/src/state/progress.ts`.

### Task container convention

Each `tasks/taskNN-*/` has a `Dockerfile` plus an `entrypoint.sh` that:

1. Starts with `set -euo pipefail`.
2. Validates required env vars with `: "${FLAG_TASKNN_FOO:?missing FLAG_TASKNN_FOO}"`.
3. Renders any templated data (e.g. `envsubst` for dnsmasq hosts).
4. `exec`s its service in the foreground.

Env vars are provided via `env_file: ${CTF_SECRETS_DIR}/taskNN.env` in
`docker-compose.yml`. `CTF_SECRETS_DIR` is exported by `spin-up.sh` to
`secrets/<instance>` so each Compose project reads its own flag slices.

### Multi-instance topology

- Each instance is a Compose project named `ctf-<instance>` (exported as
  `COMPOSE_PROJECT_NAME` by `spin-up.sh`).
- Bridge network `ctfnet` — subnet is auto-allocated by Docker from its
  default address pool. No fixed IPs.
- **Compose service keys are the themed hostnames themselves**: `mercury`,
  `mars-hop`, `venus`, `earth-logs`, `jupiter-api`, `saturn-crypto`,
  `neptune-final`, plus `hub`. This is deliberate — container names leak
  into `nmap` reverse DNS (`<project>-<service>-<replica>.<network>`), so
  task-themed names prevent `ctf-alice-task02-portscan-1` giving the game
  away. Each service also has a matching `networks.ctfnet.aliases` entry.
- **Decoys use plain themed names** (`pluto`, `titan`, …) with no
  `decoy-` prefix, for the same reason — the intern can't distinguish
  them from real services by name pattern alone, they actually have to
  probe.
- Every service (hub, tasks, decoys) runs with `restart: unless-stopped`.
  Stacks auto-start on host boot and recover from crashes, but stay down
  after an explicit `docker compose stop` or `./tear-down.sh`.
- `hub/entrypoint.sh` resolves `venus` at boot via `getent hosts` and
  prepends that IP to `/etc/resolv.conf` so `dig` / `nslookup` hit
  `venus`'s dnsmasq first (needed for Task 6's `internal.ctf` zone).
- If you change a stable hostname, update (in lockstep):
  `docker-compose.yml` (service key + `hostname:` + alias), the relevant
  task description in `hub/app/src/tasks/index.ts`, `hub/entrypoint.sh`
  if the DNS-bootstrap host changed, `smoke-test.sh`, and `README.md`
  (architecture diagram + task details).

## Tasks at a glance

| # | Title                   | Host            | Answer source                       | Depends on |
|---|-------------------------|-----------------|-------------------------------------|------------|
| 1 | Who's on the wire?      | (hub scans net) | `FLAG_TASK01` = decoy CSV           | —          |
| 2 | Find the hidden door    | `mercury`       | `FLAG_TASK02` = port                | —          |
| 3 | What did it say?        | `mercury`       | `FLAG_TASK03` = base64 of Task 4    | Task 2     |
| 4 | Crack the shell         | hub (honor)     | `FLAG_TASK04` = plaintext           | Task 3     |
| 5 | Jump to the next box    | `mars-hop`      | `FLAG_TASK05` = `/home/pivot/flag.txt` | Task 2 (hop.txt served by mercury) |
| 6 | What's in a name?       | `venus` (DNS)   | `FLAG_TASK06` = TXT record          | Task 4 (hostname derived) |
| 7 | Needle in a haystack    | `earth-logs`    | `FLAG_TASK07` = `TX-XXXXXX` in log  | —          |
| 8 | The API is the map      | `jupiter-api`   | `FLAG_TASK08` = secret field        | Task 4 (auth token) |
| 9 | One-time what?          | `saturn-crypto` | `FLAG_TASK09` = ct XOR key          | —          |
|10 | Prove it                | `neptune-final` | `FLAG_TASK10` = sha256 of Task 1..9 | all        |

Task 04's plaintext is the central seed — miss it and Tasks 6 and 8 are
unsolvable. Tasks 1 and 4 have no backing container (Task 1 scans the
existing stack; Task 4 is a pure client-side exercise on the hub, with
the intern's `base64` decoder saved to `~/solutions/task04.<ext>` for
mentor review).

## Things to watch when editing

- **Generator ordering** (`scripts/generate-flags.sh`) — Task 04
  plaintext must be generated before anything that depends on it. The
  script takes the target secrets directory as its first arg; default is
  `secrets/default`.
- **No answers in TypeScript** — `hub/app/src/tasks/index.ts` holds
  titles, descriptions, hints. Only `secrets/<instance>/hub.env` knows
  the answers; the TUI always asks the setuid helper via
  `spawnSync('/usr/local/bin/ctf-verify', ...)`.
- **Adding a new task** — update in this order:
  1. `scripts/generate-flags.sh` — generate flag + write env slice into
     `$SECRETS_DIR/taskNN.env` + extend hub.env write-out.
  2. `docker-compose.yml` — new service keyed by its themed hostname,
     with `env_file: ${CTF_SECRETS_DIR}/taskNN.env`, `hostname:`,
     `networks.ctfnet.aliases`, and `restart: unless-stopped`.
  3. `tasks/taskNN-*/` — new `Dockerfile` + `entrypoint.sh` that
     validates required env vars and execs the service.
  4. `hub/app/src/state/progress.ts` — extend `TaskId`.
  5. `hub/app/src/tasks/index.ts` — title, description, hints, estimate.
  6. `smoke-test.sh` — end-to-end check against the running service.
  7. `README.md` — table + Task details entry.
- **Task 10 expected hash** — `FLAG_TASK10_EXPECTED` is the sha256 of
  `FLAG_TASK01..FLAG_TASK09` joined with `\n`, **no trailing newline**.
  Three places encode this and must stay in sync:
  - `scripts/generate-flags.sh` (the computed value).
  - `tasks/task10-final/entrypoint.sh`'s served `/expected.sha256`.
  - `smoke-test.sh`'s final assertion.
- **ESM-only TypeScript** — in Ink sources, relative imports must end in
  `.js` even though the file is `.ts`/`.tsx`. `tsconfig.json` uses
  NodeNext module resolution.
- **Hostname changes** — if you rename one of `mercury`, `mars-hop`,
  `venus`, `earth-logs`, `jupiter-api`, `saturn-crypto`, `neptune-final`,
  update the Compose service key, `hostname:`, the alias, the task
  description in the Ink app, `smoke-test.sh`, and the README's
  architecture section. `hub/entrypoint.sh` additionally hardcodes
  `venus` as the DNS bootstrap host.

## Key paths

```
scripts/generate-flags.sh            # all randomness; one pass per spin-up
scripts/lib/random.sh                # rand_hex, rand_pronounceable, rand_triple, ...
scripts/lib/wordlist.txt             # ~200 pronounceable words for Task 4 plaintext etc.

hub/Dockerfile                       # multi-stage: builder (C helpers + Ink) → runtime
hub/entrypoint.sh                    # perms on /etc/ctf/*, resolv.conf prepend, sshd -D
hub/sshd_config                      # PermitRootLogin no, PasswordAuthentication yes, AllowUsers intern
hub/bin/hub-shell                    # login shell — requires a TTY, execs Ink app
hub/helpers/ctf-verify.c             # setuid: answer check
hub/helpers/ctf-reveal.c             # setuid: mentor-password-gated reveal
hub/app/src/index.tsx                # render loop + drop-to-shell
hub/app/src/App.tsx                  # top-level Ink component
hub/app/src/tasks/index.ts           # TASK METADATA (no answers!)
hub/app/src/state/progress.ts        # TaskId, persistence
hub/app/src/verify/verify.ts         # spawnSync → ctf-verify

tasks/task02-portscan/               # mercury — HTTP on random port + /hop.txt for Task 5
tasks/task05-ssh-hop/                # mars-hop — sshd with pivot user
tasks/task06-dns/                    # venus — dnsmasq serving internal.ctf
tasks/task07-logs/                   # earth-logs — synthetic access.log with one 500
tasks/task08-api/                    # jupiter-api — tiny Python JSON API
tasks/task09-crypto/                 # saturn-crypto — ct + key
tasks/task10-final/                  # neptune-final — /expected.sha256

secrets/<instance>/                  # gitignored; created per spin-up
  hub.env                            # root:root 0600 — the full flag map
  taskNN.env                         # per-task slice (mode 0600)
  mentor.hash                        # SHA-512 crypt of mentor password
  override.yml                       # per-instance decoy services
  .instance.env                      # COMPOSE_PROJECT_NAME, CTF_SSH_PORT — read by tear-down.sh
```

## Non-obvious things worth remembering

- `spin-up.sh` auto-picks the lowest free port ≥ 2222 if `CTF_SSH_PORT` is
  unset, so two consecutive spin-ups give two different ports. The chosen
  port is persisted in `secrets/<instance>/.instance.env`.
- The `x-no-proxy` YAML anchor in `docker-compose.yml` exists to wipe
  `HTTP(S)_PROXY` at runtime — it's only needed at build time for apt/apk
  mirrors, and a corporate proxy intercepting bare-hostname traffic
  (`mercury`, `venus`, …) inside the CTF breaks everything.
- Task 04 enforcement is **honor-system**: the flag is accepted by anyone
  submitting the correct plaintext. The mentor checks
  `~/solutions/task04.*` to confirm the intern wrote their own decoder
  instead of running `base64 -d`.
- The `intern` SSH password (`ctf`) is fixed and **not** the challenge.
  The challenge starts after login.
- The TUI runs as `intern`'s **login shell**, so exiting Ink (`q`) ends
  the SSH session — there is no outer bash to fall back to.
