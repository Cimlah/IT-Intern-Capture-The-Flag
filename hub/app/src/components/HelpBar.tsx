import React from 'react';
import { Box, Text } from 'ink';

export function HelpBar(): React.ReactElement {
  const resetEnabled = process.env.CTF_ALLOW_RESET === '1';
  return (
    <Box borderStyle="single" borderColor="gray" paddingX={1} marginTop={1}>
      <Text color="gray">
        ↑↓ navigate · <Text color="yellow">a</Text> answer · <Text color="yellow">h</Text> hint · <Text color="yellow">d</Text> drop to shell · {resetEnabled && <><Text color="yellow">r</Text> reset · </>}<Text color="yellow">q</Text> quit
      </Text>
    </Box>
  );
}
