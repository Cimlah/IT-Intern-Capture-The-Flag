import type { TaskId } from '../state/progress.js';

export interface TaskDef {
  id: TaskId;
  index: number;
  title: string;
  description: string;
  hints: string[];
  estimatedMinutes: number;
}

export const TASKS: TaskDef[] = [
  {
    id: 'task01',
    index: 1,
    title: "Who's on the wire?",
    estimatedMinutes: 15,
    hints: [
      'Check your own interface first: `ip addr` shows the subnet you\'re in.',
      'An nmap ping sweep over the /24 will list every live host: `nmap -sn 10.42.0.0/24`.',
      'Reverse DNS turns IPs into names: `getent hosts <ip>` or `dig -x <ip>`.',
      'The target set is fixed — anything NOT in that list is a decoy.',
    ],
    description:
`You have just SSHed into the CTF hub. There are other hosts on this network.
Some are TARGETS you will probe in later tasks; the rest are DECOYS that exist
only to make you actually scan instead of guessing. The decoy set is different
every time this CTF instance is spun up.

The seven TARGETS (fixed across instances) are:

    mercury      venus          earth-logs     mars-hop
    jupiter-api  saturn-crypto  neptune-final

Discover every live host on the hub's subnet. Anything that is NOT in the
target list above is a decoy.

Submit a sorted, lowercase, comma-separated list of every DECOY hostname.
Example format:
    alpha,bravo,charlie

Tools on the hub:  ip, nmap, getent, dig`,
  },
  {
    id: 'task02',
    index: 2,
    title: 'Find the hidden door',
    estimatedMinutes: 15,
    hints: [
      'A full-range TCP connect scan: `nmap -p1-65535 -sT mercury`.',
      'nmap is slow over 65k ports — add `-T4` for speed, or scan in chunks.',
      'You can also try `nc -zv mercury 1-65535` if nmap is unavailable.',
    ],
    description:
`Host \`mercury\` is running an HTTP server on a single, non-standard port.
Scan the host's TCP ports and find the open one.

Submit the port number (just the integer).

Tools on the hub:  nmap, nc, curl`,
  },
  {
    id: 'task03',
    index: 3,
    title: 'What did it say?',
    estimatedMinutes: 10,
    hints: [
      'curl is your friend: `curl http://mercury:<port>/`',
      'The response body is ONE line — paste it verbatim including the trailing `=` padding.',
    ],
    description:
`Make an HTTP GET request to the port you discovered in Task 2 on host
\`mercury\`. The server responds with a single base64-encoded string in the
response body.

Submit the base64 string exactly as the server sent it (including any
trailing \`=\` padding).

Tools on the hub:  curl, wget`,
  },
  {
    id: 'task04',
    index: 4,
    title: 'Crack the shell',
    estimatedMinutes: 20,
    hints: [
      'base64 alphabet: A–Z, a–z, 0–9, +, /, with = as padding. 4 input chars → 3 output bytes.',
      'Python: `int.from_bytes` or implement the lookup table yourself.',
      'Save your solution to ~/solutions/task04.py (or .js, .sh) — your mentor will look at it.',
    ],
    description:
`Write your OWN script to decode the base64 string from Task 3, in a language
of your choice (Python, JavaScript, bash — whatever you are comfortable with).

Submit the decoded plaintext.

NOTE: using the \`base64 -d\` command defeats the purpose of this exercise.
Implement the decode yourself. Save your script to
    ~/solutions/task04.<ext>
so your mentor can review it.

Tools on the hub:  python3, node, bash, xxd`,
  },
  {
    id: 'task05',
    index: 5,
    title: 'Jump to the next box',
    estimatedMinutes: 25,
    hints: [
      'Revisit mercury — it serves more than just the index page. `curl http://mercury:<port>/hop.txt`.',
      'Use `ssh pivot@mars-hop` with the password you just found.',
      'The flag file is at /home/pivot/flag.txt once you are logged in.',
    ],
    description:
`There is another host on the network named \`mars-hop\`. It runs its own SSH
server and has an account named \`pivot\`. The password for that account is
hidden on \`mercury\` at the path \`/hop.txt\` (same port as Task 2).

Retrieve the password, SSH in as \`pivot\`, and read the file
\`/home/pivot/flag.txt\`.

Submit the contents of flag.txt.

Tools on the hub:  curl, ssh, cat`,
  },
  {
    id: 'task06',
    index: 6,
    title: "What's in a name?",
    estimatedMinutes: 25,
    hints: [
      'Compute the sha256 of the plaintext: `printf %s "your-plaintext" | sha256sum`.',
      'The first 8 hex chars of that hash build the hostname: h-XXXXXXXX.internal.ctf.',
      'Query the TXT record: `dig TXT h-XXXXXXXX.internal.ctf +short`.',
    ],
    description:
`There is an internal DNS zone at \`internal.ctf\` served by host \`venus\`.
Somewhere in it is a host whose TXT record contains a flag.

The hostname you need is derived from your Task 4 plaintext:

    1. compute sha256(plaintext)
    2. take the FIRST 8 hex characters of that digest
    3. build the name: h-<those 8 chars>.internal.ctf

Query that host's TXT record and submit the value.

Tools on the hub:  sha256sum, dig, nslookup`,
  },
  {
    id: 'task07',
    index: 7,
    title: 'Needle in a haystack',
    estimatedMinutes: 25,
    hints: [
      'Download the log first: `curl -o access.log http://earth-logs/access.log`.',
      'The interesting request is the ONLY one with HTTP status 500 in the combined log format.',
      'grep for \' 500 \' with the surrounding spaces to avoid matching payload sizes.',
      'The transaction ID starts with `TX-`.',
    ],
    description:
`Host \`earth-logs\` serves a large Apache-style access log at
\`http://earth-logs/access.log\`. Somewhere in it, exactly one request returned
an HTTP 500 status, and that line also contains a transaction ID of the form
\`TX-XXXXXX\`.

Find the transaction ID.

Submit the full ID including the \`TX-\` prefix.

Tools on the hub:  curl, grep, awk, sed`,
  },
  {
    id: 'task08',
    index: 8,
    title: 'The API is the map',
    estimatedMinutes: 30,
    hints: [
      'GET http://jupiter-api:8080/ returns a JSON list of endpoints.',
      'One endpoint returns 401 without an auth header. Look carefully.',
      'The header name is X-Auth-Token. The value is your Task 4 plaintext.',
      'Use `jq` to pull the secret field out of the JSON response.',
    ],
    description:
`Host \`jupiter-api\` serves a tiny JSON API on port 8080. GET / lists its
endpoints. Most of them return boring data. ONE endpoint requires an
\`X-Auth-Token\` header; the token value is your Task 4 plaintext.

Authenticate, find the endpoint that returns a JSON object with a \`secret\`
field, and submit the secret's value.

Tools on the hub:  curl, jq`,
  },
  {
    id: 'task09',
    index: 9,
    title: 'One-time what?',
    estimatedMinutes: 35,
    hints: [
      'Both files are hex-encoded. Decode them with `xxd -r -p` or in your script.',
      'The two buffers are the same length. XOR them byte by byte: plaintext = ct XOR key.',
      'Python: `bytes(a ^ b for a,b in zip(ct, key))`.',
    ],
    description:
`Host \`saturn-crypto\` serves two files:
    http://saturn-crypto/ct     — ciphertext as lowercase hex
    http://saturn-crypto/key    — key as lowercase hex

Both are the same length. XOR them together to recover the ASCII plaintext.

Submit the ASCII plaintext exactly as printed.

Tools on the hub:  curl, python3, xxd`,
  },
  {
    id: 'task10',
    index: 10,
    title: 'Prove it',
    estimatedMinutes: 40,
    hints: [
      'Canonical order is Task 1 through Task 9. Join them with a single LF (\\n) — no trailing newline.',
      'Python one-liner: `hashlib.sha256("\\n".join(flags).encode()).hexdigest()`.',
      'Sanity check your result against http://neptune-final/expected.sha256 before submitting.',
    ],
    description:
`Write a program (any language) that:

    1. takes all 9 previous flags in order (Task 1 through Task 9)
    2. joins them with a single newline character (\\n), no trailing newline
    3. computes the sha256 of that byte string
    4. prints the lowercase hex digest

Sanity-check your output against:
    http://neptune-final/expected.sha256

When your program prints the expected hash, submit the hex digest here.

Tools on the hub:  python3, node, sha256sum, curl`,
  },
];

if (TASKS.length !== 10) {
  throw new Error(`Expected 10 tasks in registry, got ${TASKS.length}`);
}

export function taskById(id: TaskId): TaskDef | undefined {
  return TASKS.find(t => t.id === id);
}
