import React from 'react';
import { Box, Text } from 'ink';

interface Props {
  kind: 'success' | 'error';
  message: string;
}

export function Feedback({ kind, message }: Props): React.ReactElement {
  const color = kind === 'success' ? 'green' : 'red';
  const prefix = kind === 'success' ? '✓' : '✗';
  return (
    <Box borderStyle="single" borderColor={color} paddingX={1} marginTop={1}>
      <Text color={color} bold>{prefix} {message}</Text>
    </Box>
  );
}
