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

## Quick start — multi-instance

Every CTF instance is a **named Compose project** with its own network, its
own flags, and its own host SSH port. Run as many as your server's RAM allows.

```bash
./spin-up.sh alice           # first instance — auto-picks port 2222
./spin-up.sh bob             # second instance — auto-picks port 2223
ssh -t intern@localhost -p 2222   # alice's hub; password: ctf
ssh -t intern@localhost -p 2223   # bob's hub;   password: ctf

./tear-down.sh alice -y      # tear down just alice (bob keeps running)
./tear-down.sh --all -y      # tear down every instance on this host
```

If you omit the instance name, both scripts default to `default`:

```bash
./spin-up.sh                 # equivalent to ./spin-up.sh default
./tear-down.sh               # tears down the "default" instance
```

`spin-up.sh` prints the mentor password for the instance **exactly once**
at the end of its output. Save it immediately — it is not persisted in
plaintext anywhere.

Useful flags:

| Command | Flag | Effect |
| --- | --- | --- |
| `spin-up.sh`  | `--fresh`         | Regenerate secrets even if `secrets/<name>/hub.env` already exists |
| `tear-down.sh`| `--all`           | Tear down every instance under `secrets/` |
| `tear-down.sh`| `--keep-state`    | Keep the state volume (preserves intern progress) |
| `tear-down.sh`| `--keep-secrets`  | Keep `secrets/<name>/` on disk |
| `tear-down.sh`| `-y` / `--yes`    | Skip the confirmation prompt |

Environment variables:

| Name | Default | Purpose |
| --- | --- | --- |
| `CTF_SSH_PORT`        | first free ≥2222 | Force a specific host SSH port for this spin-up |
| `CTF_MENTOR_PASSWORD` | (random)         | Override the generated mentor password |
| `CTF_ALLOW_RESET`     | `0`              | If `1`, enables the in-TUI reset key |

## Realistic concurrent-instance cap

Each instance is ~11 containers (hub + 7 task services + 3–5 decoys) and
idles at roughly **500 MB of RAM**. CPU is near-zero. Disk is dominated by
the one-time image builds (~800 MB total), which are **shared across all
instances** on the same host.

RAM-bounded cap (leave ~25% headroom for the host):

| Host RAM | Concurrent instances |
|---------:|---------------------:|
|   8 GB   |                ~13   |
|  16 GB   |                ~26   |
|  32 GB   |                ~53   |
|  64 GB   |               ~106   |

Docker auto-allocates a private subnet per instance from its default
address pool. Out of the box that pool holds roughly 31 networks — plenty
for small deployments. If you plan to run **more than ~20 instances
simultaneously**, expand the pool in `/etc/docker/daemon.json`:

```json
{
  "default-address-pools": [
    { "base": "10.200.0.0/16", "size": 24 }
  ]
}
```

Then `systemctl restart docker`. That reserves 256 `/24` subnets
exclusively for Docker networks — more than enough to saturate any
realistic RAM budget.

## Smoke test

After a spin-up, run `./smoke-test.sh <name>` from the host (or just
`./smoke-test.sh` for the default instance). It verifies:

- all services are running
- the hub can resolve every task container
- each task's backing service answers correctly with the expected flag
- `intern` cannot read `/etc/ctf/hub.env` (privilege separation)
- `ctf-verify` rejects wrong answers and accepts correct ones
- the Ink TUI passes `--self-check`

The script exits non-zero on any failure.

## The tasks

Ten sequential tasks, unlocked one at a time. The intern sees locked task
titles but not their descriptions. Total wall-clock budget is **240 minutes**
(4 hours); expect 4.5–5 h with realistic friction.

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

### Task details

#### 1. Who's on the wire? *(15 min)*

The intern has just landed on the hub. Other hosts exist on the private
Docker network — seven are **targets** (`mercury`, `venus`, `earth-logs`,
`mars-hop`, `jupiter-api`, `saturn-crypto`, `neptune-final`) and 3–5 are
randomized **decoys** named after moons and dwarf planets. The intern must
ping-sweep the subnet, reverse-resolve the live hosts, subtract the target
list, and submit the sorted CSV of decoy hostnames. The decoy set changes on
every spin-up, so this answer is unique per instance.
Tools: `ip`, `nmap -sn`, `getent hosts`, `dig -x`.

#### 2. Find the hidden door *(15 min)*

Host `mercury` runs an HTTP server on a single, randomized high port
(1024–65000, avoiding 22/2222). The intern scans all 65535 TCP ports and
submits the one open integer.
Tools: `nmap -p-`, `nc -zv`.

#### 3. What did it say? *(10 min)*

Fetch `http://mercury:<port>/` and submit the base64 string the server
returns — verbatim, including any `=` padding. The response body is a single
line so the intern can paste it directly into the TUI.
Tools: `curl`, `wget`.

#### 4. Crack the shell *(20 min)* — **honor system**

The intern writes their **own** base64 decoder (Python, Node, bash, …) to
decode the Task 3 string, and saves the script to `~/solutions/task04.<ext>`
for mentor review. Submit the decoded plaintext (a pronounceable
`word-1234`-style token). Using `base64 -d` defeats the exercise — the
mentor checks the saved script.
Tools: `python3`, `node`, `bash`, `xxd`.

> **Flag chaining.** This plaintext is reused as (a) the derivation input
> for the Task 6 DNS hostname and (b) the Task 8 auth token. Get Task 4
> right and two later tasks fall out of it; get it wrong and neither
> works.

#### 5. Jump to the next box *(25 min)*

Host `mars-hop` runs sshd with a user `pivot`. The password is hidden as a
plain file at `http://mercury:<port>/hop.txt`. The intern fetches the
password, SSHes in with `ssh pivot@mars-hop`, reads `/home/pivot/flag.txt`,
and submits its contents.
Tools: `curl`, `ssh`, `cat`.

#### 6. What's in a name? *(25 min)*

Host `venus` runs dnsmasq serving the `internal.ctf` zone. The DNS name the
intern needs is **derived from the Task 4 plaintext**:

1. `sha256(plaintext)` → 64 hex chars
2. take the first 8 hex chars
3. build `h-<those-8-chars>.internal.ctf`

`dig TXT <that-name>` returns the flag as the TXT record value.
Tools: `sha256sum`, `dig`, `nslookup`.

#### 7. Needle in a haystack *(25 min)*

Host `earth-logs` serves a synthetic Apache-style access log at
`http://earth-logs/access.log` with several hundred lines of noise. Exactly
one entry has HTTP status 500, and that line also contains a transaction ID
`TX-XXXXXX`. The intern submits the full transaction ID.
Tools: `curl`, `grep`, `awk`, `sed`.

#### 8. The API is the map *(30 min)*

Host `jupiter-api` runs a small Python JSON API on port 8080. `GET /` lists
endpoints. Most return boring JSON; one endpoint requires an `X-Auth-Token`
header whose value is the **Task 4 plaintext**. Authenticate, find the
endpoint that returns a `secret` field, submit its value.
Tools: `curl`, `jq`.

#### 9. One-time what? *(35 min)*

Host `saturn-crypto` serves two hex-encoded files of equal length:
`http://saturn-crypto/ct` (ciphertext) and `http://saturn-crypto/key`. XOR
them byte-for-byte to recover an ASCII plaintext sentence. Submit the
plaintext verbatim.
Tools: `curl`, `python3`, `xxd`.

#### 10. Prove it *(40 min)*

Write a program that (a) concatenates all nine previous flags in order
joined by `\n` (no trailing newline), (b) computes sha256, (c) prints the
lowercase hex digest. Host `neptune-final` exposes the expected digest at
`http://neptune-final/expected.sha256` for sanity checking. Submit the
hash.
Tools: `python3`, `node`, `sha256sum`, `curl`.

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
host ──► ssh -p <ssh_port> ──► hub ┬──► mercury        (task02/03/05 http)
                                   ├──► mars-hop       (task05 ssh)
                                   ├──► venus          (task06 dns)
                                   ├──► earth-logs     (task07 logs)
                                   ├──► jupiter-api    (task08 api)
                                   ├──► saturn-crypto  (task09 ct/key)
                                   ├──► neptune-final  (task10 expected hash)
                                   └──► 3–5 decoy containers
```

- **`ctfnet`**: one bridge network per instance, with a subnet that Docker
  auto-allocates from its default address pool. Compose service keys are
  the themed hostnames themselves (`mercury`, `mars-hop`, …) and the
  matching `networks.ctfnet.aliases` register the same names inside Docker
  DNS — two instances can both have a `mercury` without conflict because
  each resolves only inside its own network. Decoys are plain service
  names too (`pluto`, `titan`, …), so `nmap` cannot distinguish them from
  real services by name pattern.
- **Restart policy.** Every service (hub, task containers, decoys) runs
  with `restart: unless-stopped`. After `./spin-up.sh` the stack will
  auto-start on host boot and recover from container crashes, but will
  stay down after `./tear-down.sh` or an explicit `docker compose stop`.
- **`secrets/<instance>/`** (gitignored): written by
  `scripts/generate-flags.sh` for each named instance. `hub.env` is the
  authoritative flag map and is mounted into the hub as `root:root 0600`.
  Per-task slices are mounted only into the containers that need them.
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
  moon/dwarf-planet pool and writes `secrets/<name>/override.yml` so compose
  actually runs those containers. Task 01's answer is the decoy CSV, so it
  genuinely changes every spin-up.
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
│   ├── generate-flags.sh        # single randomization pass; writes secrets/<name>/
│   └── lib/random.sh            # hex, word, sentence, XOR helpers
├── secrets/<instance>/          # gitignored — one subdir per named instance
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