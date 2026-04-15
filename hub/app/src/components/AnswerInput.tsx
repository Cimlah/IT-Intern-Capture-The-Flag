import React, { useState } from 'react';
import { Box, Text, useInput } from 'ink';
import TextInput from 'ink-text-input';

interface Props {
  prompt: string;
  onSubmit: (value: string) => void;
  onCancel: () => void;
}

export function AnswerInput({ prompt, onSubmit, onCancel }: Props): React.ReactElement {
  const [value, setValue] = useState<string>('');
  useInput((_input, key) => {
    if (key.escape) onCancel();
  });
  return (
    <Box borderStyle="round" borderColor="yellow" paddingX={1} marginTop={1}>
      <Text color="yellowBright">{prompt}</Text>
      <TextInput value={value} onChange={setValue} onSubmit={() => onSubmit(value)} />
    </Box>
  );
}
