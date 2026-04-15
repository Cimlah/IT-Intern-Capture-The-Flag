import React from 'react';
import { Box, Text } from 'ink';

interface Props {
  startedAt: string;
}

function formatElapsed(ms: number): string {
  const total = Math.max(0, Math.floor(ms / 1000));
  const h = Math.floor(total / 3600);
  const m = Math.floor((total % 3600) / 60);
  const s = total % 60;
  const pad = (n: number) => n.toString().padStart(2, '0');
  return `${pad(h)}:${pad(m)}:${pad(s)}`;
}

export function Header({ startedAt }: Props): React.ReactElement {
  const [now, setNow] = React.useState(() => Date.now());
  React.useEffect(() => {
    const t = setInterval(() => setNow(Date.now()), 1000);
    return () => clearInterval(t);
  }, []);
  const elapsed = formatElapsed(now - new Date(startedAt).getTime());
  return (
    <Box borderStyle="round" borderColor="cyan" paddingX={1} flexDirection="row" justifyContent="space-between">
      <Text color="cyanBright" bold>CTF Hub — Intern Challenge</Text>
      <Text color="gray">elapsed {elapsed}</Text>
    </Box>
  );
}
