import React from 'react';
import { Box, Text } from 'ink';
import type { TaskDef } from '../tasks/index.js';
import type { TaskId, TaskStatus } from '../state/progress.js';

interface Props {
  tasks: TaskDef[];
  statuses: Record<TaskId, TaskStatus>;
  selectedIdx: number;
}

function icon(status: TaskStatus): string {
  if (status === 'completed') return '[+]';
  if (status === 'current') return '[*]';
  return '[ ]';
}

function color(status: TaskStatus, selected: boolean): string {
  if (selected) return 'yellowBright';
  if (status === 'completed') return 'green';
  if (status === 'current') return 'cyan';
  return 'gray';
}

export function TaskList({ tasks, statuses, selectedIdx }: Props): React.ReactElement {
  return (
    <Box flexDirection="column" borderStyle="single" borderColor="gray" paddingX={1}>
      <Text color="white" bold>Tasks</Text>
      {tasks.map((t, i) => {
        const st = statuses[t.id];
        const sel = i === selectedIdx;
        const label = st === 'locked' ? `Task ${t.index}` : `Task ${t.index} — ${t.title}`;
        return (
          <Text key={t.id} color={color(st, sel)}>
            {sel ? '▶ ' : '  '}{icon(st)} {label}
          </Text>
        );
      })}
    </Box>
  );
}
