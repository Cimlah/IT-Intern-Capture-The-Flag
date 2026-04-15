import { spawnSync } from 'node:child_process';
import type { TaskId } from '../state/progress.js';

const HELPER = process.env.CTF_VERIFY_PATH ?? '/usr/local/bin/ctf-verify';

export function verifyAnswer(taskId: TaskId, answer: string): boolean {
  const res = spawnSync(HELPER, [taskId, answer], {
    stdio: ['ignore', 'pipe', 'pipe'],
    encoding: 'utf8',
  });
  return res.status === 0;
}
