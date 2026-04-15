# IT Intern Capture-The-Flag

A one-click, Docker-based Capture-The-Flag training environment for IT interns.
The intern SSHes into a "hub" container that runs a custom React Ink TUI as
their login shell, and solves ten Linux / networking / programming tasks
against a set of purpose-built target containers on a private Docker network.

Each spin-up regenerates all flags, so two interns running the stack side by
side will see different answers. Total wall-clock budget is roughly **4 hours**
for a comfortable-with-CLI intern; expect 4.5–5 h with realistic friction.

## Requirements

- Docker 24+ with the `docker compose` plugin
- `bash`, `openssl`, `python3` on the host (for flag generation and smoke tests)
- An SSH client that supports `-t` (PTY allocation) — including Windows OpenSSH,
  PuTTY, or the built-in Terminal on macOS/Linux

## Quick start

```bash
./spin-up.sh                 # generate flags, build, start, print mentor password
ssh -t intern@localhost -p 2222   # password: ctf
./tear-down.sh               # stop everything and wipe state + secrets
```

`spin-up.sh` prints the mentor password **exactly once** at the end of its
output. Save it immediately — it is not persisted in plaintext anywhere.

Useful flags:

| Command | Flag | Effect |
| --- | --- | --- |
| `spin-up.sh`  | `--fresh`         | Regenerate secrets even if `secrets/` already exists |
| `tear-down.sh`| `--keep-state`    | Keep the `state` volume (preserves intern progress) |
| `tear-down.sh`| `--keep-secrets`  | Keep `secrets/*.env` and `secrets/mentor.hash` |
| `tear-down.sh`| `-y` / `--yes`    | Skip the confirmation prompt |

Environment variables:

| Name | Default | Purpose |
| --- | --- | --- |
| `CTF_SSH_PORT`        | `2222` | Host port mapped to the hub's sshd |
| `CTF_MENTOR_PASSWORD` | (random) | Override the generated mentor password |
| `CTF_ALLOW_RESET`     | `0`    | If `1`, enables the in-TUI reset key |

## Smoke test

After a spin-up, run `./smoke-test.sh` from the host. It verifies:

- all services are running
- the hub can resolve every task container
- each task's backing service answers correctly with the expected flag
- `intern` cannot read `/etc/ctf/hub.env` (privilege separation)
- `ctf-verify` rejects wrong answers and accepts correct ones
- the Ink TUI passes `--self-check`

The script exits non-zero on any failure.

## The tasks

Ten sequential tasks, unlocked one at a time. The intern can see locked task
titles but not their descriptions.

| # | Title | Focus | Est. |
| - | ----- | ----- | ---- |
| 1 | Who's on the wire?     | `nmap -sn`, reverse DNS        | 15 m |
| 2 | Find the hidden door   | full-range port scan           | 15 m |
| 3 | What did it say?       | HTTP GET                       | 10 m |
| 4 | Crack the shell        | base64 — **write your own**    | 20 m |
| 5 | Jump to the next box   | SSH pivot via password file    | 25 m |
| 6 | What's in a name?      | sha256 → DNS TXT lookup        | 25 m |
| 7 | Needle in a haystack   | log forensics (HTTP 500)       | 25 m |
| 8 | The API is the map     | auth'd REST call               | 30 m |
| 9 | One-time what?         | XOR crypto                     | 35 m |
|10 | Prove it               | sha256 of all prior flags      | 40 m |

**Flag chaining.** Task 04's plaintext is deliberately reused: it is the input
that generates the Task 06 DNS hostname and the Task 08 auth token. Blowing
through Task 04 with `base64 -d` is detectable by the mentor because interns
are required to save their hand-written decoder to `~/solutions/task04.*`.

## Mentor workflow

Everything mentors need lives inside the hub container:

```bash
# From inside the hub:
ctf-reveal                   # prompts for mentor password, prints all flags
cat ~/solutions/task04.*     # review the intern's decoder
```

`ctf-reveal` is a setuid C helper. It reads the bcrypt-style hash at
`/etc/ctf/mentor.hash` and compares the user's password in constant time; it
sleeps on failure to slow brute-force attempts. The plaintext mentor password
is never stored on disk.

If the mentor password is lost, run `./spin-up.sh --fresh` to generate a new
instance (this also rotates every flag).

## Architecture

```
host ──► ssh -p 2222 ──► ctf-hub ┬──► mercury      (task02/03/05 http)
                                 ├──► mars-hop   (task05 ssh)
                                 ├──► venus         (task06 dns)
                                 ├──► earth-logs    (task07 logs)
                                 ├──► jupiter-api   (task08 api)
                                 ├──► saturn-crypto (task09 ct/key)
                                 ├──► neptune-final (task10 expected hash)
                                 └──► 3–5 decoy containers
```

- **`ctfnet`**: bridge network, subnet `10.42.0.0/24`, fixed IPs per service.
- **`secrets/`** (gitignored): written by `scripts/generate-flags.sh`.
  `hub.env` is the authoritative flag map and is mounted into the hub as
  `root:root 0600`. Per-task slices are mounted only into the containers
  that need them.
- **Ink TUI** (`hub/app/`): TypeScript / React Ink 5 running as the login
  shell of user `intern`. Verifies answers by shelling out to the `ctf-verify`
  setuid helper; it never reads `hub.env` directly.
- **Setuid helpers** (`hub/helpers/*.c`): `ctf-verify` answers the Ink app's
  yes/no verification query; `ctf-reveal` is the mentor-password-gated answer
  dump. Both are installed `4755 root:root` during the image build.

## Known limitations

- **Task 01 target list is stable across instances.** The seven target
  container hostnames (`mercury`, `jupiter-api`, `earth-logs`, `neptune-final`,
  `mars-hop`, `venus`, `saturn-crypto`) are fixed in `docker-compose.yml` so
  later task descriptions can refer to them by name. Only the **decoy** set
  varies per instance — `scripts/generate-flags.sh` picks 3–5 names from a
  moon/dwarf-planet pool and writes `docker-compose.override.yml` so compose
  actually runs those containers. Task 01's answer is the decoy CSV, so it
  genuinely changes every spin-up.
- **Single-user stack.** One `docker compose` stack serves one intern. Run one
  copy per intern, each with a different `CTF_SSH_PORT`.
- **SSH requires `-t`.** The hub login shell refuses to start without a PTY
  and prints a reconnect hint. This is primarily a Windows SSH reminder.
- **Task 04 is honor-system.** The flag is accepted by anyone who submits the
  correct plaintext; there is no runtime check that the intern did not just
  run `base64 -d`. The mentor enforces this by reviewing `~/solutions/task04.*`.

## Directory layout

```
.
├── docker-compose.yml
├── spin-up.sh / tear-down.sh / smoke-test.sh
├── scripts/
│   ├── generate-flags.sh        # single randomization pass; writes secrets/
│   └── lib/random.sh            # hex, word, sentence, XOR helpers
├── secrets/                     # gitignored — created at spin-up
├── hub/
│   ├── Dockerfile               # multi-stage: builder (helpers + Ink) + runtime
│   ├── entrypoint.sh            # host keys, resolv.conf, sshd -D
│   ├── sshd_config / motd
│   ├── bin/hub-shell            # login shell → execs the Ink TUI
│   ├── helpers/                 # ctf-verify.c, ctf-reveal.c
│   └── app/                     # TypeScript Ink TUI
└── tasks/
    ├── task02-portscan/         # mercury — HTTP + hop.txt for Task 05
    ├── task05-ssh-hop/          # mars-hop — sshd with pivot user
    ├── task06-dns/              # venus — dnsmasq with internal.ctf zone
    ├── task07-logs/             # earth-logs — synthetic access.log
    ├── task08-api/              # jupiter-api — Python JSON API
    ├── task09-crypto/           # saturn-crypto — ct + key
    └── task10-final/            # neptune-final — expected.sha256
```

Task 01 has no dedicated container (it scans the stack). Task 04 is pure
client-side work on the hub.
