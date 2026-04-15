import React from 'react';
import { Box, Text } from 'ink';
import type { TaskDef } from '../tasks/index.js';
import type { TaskStatus } from '../state/progress.js';

interface Props {
  task: TaskDef;
  status: TaskStatus;
  attempts: number;
  hintIndex: number;
}

export function TaskDetail({ task, status, attempts, hintIndex }: Props): React.ReactElement {
  if (status === 'locked') {
    return (
      <Box flexDirection="column" borderStyle="single" borderColor="gray" padding={1}>
        <Text color="gray" bold>Task {task.index} — locked</Text>
        <Text color="gray">Complete the earlier tasks to unlock this one.</Text>
      </Box>
    );
  }

  const headerColor = status === 'completed' ? 'green' : 'cyanBright';
  return (
    <Box flexDirection="column" borderStyle="single" borderColor={status === 'completed' ? 'green' : 'cyan'} padding={1}>
      <Box flexDirection="row" justifyContent="space-between">
        <Text color={headerColor} bold>Task {task.index} — {task.title}</Text>
        <Text color="gray">~{task.estimatedMinutes} min · attempts: {attempts}</Text>
      </Box>
      <Box marginTop={1} flexDirection="column">
        {task.description.split('\n').map((line, i) => (
          <Text key={i} color="white">{line || ' '}</Text>
        ))}
      </Box>
      {hintIndex >= 0 && task.hints.length > 0 && (
        <Box marginTop={1} flexDirection="column">
          <Text color="magentaBright" bold>Hints:</Text>
          {task.hints.slice(0, hintIndex + 1).map((h, i) => (
            <Text key={i} color="magenta">  {i + 1}. {h}</Text>
          ))}
        </Box>
      )}
      {status === 'completed' && (
        <Box marginTop={1}>
          <Text color="green" bold>✓ Solved</Text>
        </Box>
      )}
    </Box>
  );
}
