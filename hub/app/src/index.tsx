import React from 'react';
import { render } from 'ink';
import { spawnSync } from 'node:child_process';
import { App } from './App.js';
import { TASKS } from './tasks/index.js';
import { verifyAnswer } from './verify/verify.js';

const args = process.argv.slice(2);

if (args.includes('--self-check')) {
  if (TASKS.length !== 10) {
    console.error(`self-check: expected 10 tasks, got ${TASKS.length}`);
    process.exit(2);
  }
  const garbage = verifyAnswer('task01', 'this-is-definitely-not-the-answer-' + Date.now());
  if (garbage) {
    console.error('self-check: verify returned true for a garbage input');
    process.exit(2);
  }
  console.log('self-check: OK');
  process.exit(0);
}

async function main(): Promise<void> {
  // eslint-disable-next-line no-constant-condition
  while (true) {
    let dropRequested = false;
    const onDropToShell = (): void => {
      dropRequested = true;
    };
    const inst = render(<App onDropToShell={onDropToShell} />, { exitOnCtrlC: true });
    await inst.waitUntilExit();

    if (!dropRequested) break;

    process.stdout.write('\x1b[2J\x1b[H');
    console.log('--- dropping to shell — type `exit` to return to the hub ---');
    spawnSync('/bin/bash', ['--login'], { stdio: 'inherit' });
  }
}

main().catch(err => {
  console.error('hub: fatal error:', err);
  process.exit(1);
});
