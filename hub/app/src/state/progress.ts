import { readFileSync, writeFileSync, renameSync, existsSync, mkdirSync } from 'node:fs';
import { dirname } from 'node:path';

export type TaskId =
  | 'task01' | 'task02' | 'task03' | 'task04' | 'task05'
  | 'task06' | 'task07' | 'task08' | 'task09' | 'task10';

export type TaskStatus = 'locked' | 'current' | 'completed';

export interface ProgressState {
  statuses: Record<TaskId, TaskStatus>;
  attempts: Record<TaskId, number>;
  completedAt: Record<TaskId, string>;
  startedAt: string;
}

export const TASK_ORDER: TaskId[] = [
  'task01', 'task02', 'task03', 'task04', 'task05',
  'task06', 'task07', 'task08', 'task09', 'task10',
];

const STATE_PATH = process.env.CTF_STATE_PATH ?? '/var/ctf/state/intern.json';

function blankRecord<V>(value: V): Record<TaskId, V> {
  return Object.fromEntries(TASK_ORDER.map(t => [t, value])) as Record<TaskId, V>;
}

export function emptyState(): ProgressState {
  const statuses = blankRecord<TaskStatus>('locked');
  statuses.task01 = 'current';
  return {
    statuses,
    attempts: blankRecord<number>(0),
    completedAt: blankRecord<string>(''),
    startedAt: new Date().toISOString(),
  };
}

export function loadProgress(): ProgressState {
  try {
    if (!existsSync(STATE_PATH)) return emptyState();
    const raw = readFileSync(STATE_PATH, 'utf8');
    const parsed = JSON.parse(raw) as ProgressState;
    // Repair any missing keys from an older state file
    const fresh = emptyState();
    for (const k of TASK_ORDER) {
      if (!(k in parsed.statuses)) parsed.statuses[k] = fresh.statuses[k];
      if (!(k in parsed.attempts)) parsed.attempts[k] = 0;
      if (!(k in parsed.completedAt)) parsed.completedAt[k] = '';
    }
    if (!parsed.startedAt) parsed.startedAt = fresh.startedAt;
    return parsed;
  } catch {
    return emptyState();
  }
}

export function saveProgress(state: ProgressState): void {
  const dir = dirname(STATE_PATH);
  mkdirSync(dir, { recursive: true });
  const tmp = STATE_PATH + '.tmp';
  writeFileSync(tmp, JSON.stringify(state, null, 2), 'utf8');
  renameSync(tmp, STATE_PATH);
}

export function markCompleted(state: ProgressState, taskId: TaskId): ProgressState {
  const idx = TASK_ORDER.indexOf(taskId);
  const statuses = { ...state.statuses };
  const completedAt = { ...state.completedAt, [taskId]: new Date().toISOString() };
  statuses[taskId] = 'completed';
  if (idx + 1 < TASK_ORDER.length) {
    statuses[TASK_ORDER[idx + 1]!] = 'current';
  }
  return { ...state, statuses, completedAt };
}

export function incrementAttempts(state: ProgressState, taskId: TaskId): ProgressState {
  return { ...state, attempts: { ...state.attempts, [taskId]: (state.attempts[taskId] ?? 0) + 1 } };
}
