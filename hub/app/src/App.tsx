import React, { useState, useEffect } from 'react';
import { Box, Text, useApp, useInput } from 'ink';
import { Header } from './components/Header.js';
import { TaskList } from './components/TaskList.js';
import { TaskDetail } from './components/TaskDetail.js';
import { AnswerInput } from './components/AnswerInput.js';
import { Feedback } from './components/Feedback.js';
import { HelpBar } from './components/HelpBar.js';
import { TASKS } from './tasks/index.js';
import {
  ProgressState,
  TASK_ORDER,
  loadProgress,
  saveProgress,
  markCompleted,
  incrementAttempts,
  emptyState,
} from './state/progress.js';
import { verifyAnswer } from './verify/verify.js';

type ViewMode = 'list' | 'answer';

interface Props {
  onDropToShell: () => void;
}

export function App({ onDropToShell }: Props): React.ReactElement {
  const { exit } = useApp();
  const [progress, setProgress] = useState<ProgressState>(() => loadProgress());
  const [selectedIdx, setSelectedIdx] = useState<number>(() => {
    const curr = TASK_ORDER.findIndex(t => progress.statuses[t] === 'current');
    return curr >= 0 ? curr : 0;
  });
  const [mode, setMode] = useState<ViewMode>('list');
  const [feedback, setFeedback] = useState<{ kind: 'success' | 'error' | null; msg: string }>({
    kind: null,
    msg: '',
  });
  const [hintIndex, setHintIndex] = useState<number>(-1);

  useEffect(() => {
    if (feedback.kind === null) return;
    const t = setTimeout(() => setFeedback({ kind: null, msg: '' }), 3500);
    return () => clearTimeout(t);
  }, [feedback]);

  const allComplete = TASK_ORDER.every(t => progress.statuses[t] === 'completed');
  const selectedTask = TASKS[selectedIdx]!;
  const selectedStatus = progress.statuses[selectedTask.id];
  const isLocked = selectedStatus === 'locked';

  useInput((input, key) => {
    if (mode === 'answer') return;
    if (key.upArrow) {
      setSelectedIdx(i => Math.max(0, i - 1));
      setHintIndex(-1);
      return;
    }
    if (key.downArrow) {
      setSelectedIdx(i => Math.min(TASKS.length - 1, i + 1));
      setHintIndex(-1);
      return;
    }
    if (input === 'a' || key.return) {
      if (!isLocked && selectedStatus !== 'completed') setMode('answer');
      return;
    }
    if (input === 'h') {
      if (!isLocked && selectedTask.hints.length > 0) {
        setHintIndex(i => Math.min(i + 1, selectedTask.hints.length - 1));
      }
      return;
    }
    if (input === 'd') {
      onDropToShell();
      exit();
      return;
    }
    if (input === 'r' && process.env.CTF_ALLOW_RESET === '1') {
      const fresh = emptyState();
      saveProgress(fresh);
      setProgress(fresh);
      setSelectedIdx(0);
      setFeedback({ kind: 'success', msg: 'Progress reset.' });
      return;
    }
    if (input === 'q') {
      exit();
    }
  });

  const handleAnswer = (answer: string) => {
    setMode('list');
    if (!answer.trim()) return;
    const ok = verifyAnswer(selectedTask.id, answer);
    let next = incrementAttempts(progress, selectedTask.id);
    if (ok) {
      next = markCompleted(next, selectedTask.id);
      saveProgress(next);
      setProgress(next);
      setFeedback({ kind: 'success', msg: `Task ${selectedTask.index} solved.` });
      const newCurr = TASK_ORDER.findIndex(t => next.statuses[t] === 'current');
      if (newCurr >= 0) setSelectedIdx(newCurr);
    } else {
      saveProgress(next);
      setProgress(next);
      setFeedback({ kind: 'error', msg: 'Incorrect. Try again — press h for a hint.' });
    }
    setHintIndex(-1);
  };

  return (
    <Box flexDirection="column" padding={1}>
      <Header startedAt={progress.startedAt} />
      <Box flexDirection="row" marginY={1}>
        <Box width={40} flexDirection="column">
          <TaskList tasks={TASKS} statuses={progress.statuses} selectedIdx={selectedIdx} />
        </Box>
        <Box flexDirection="column" flexGrow={1} paddingX={2}>
          {allComplete ? (
            <Box borderStyle="double" borderColor="green" padding={1} flexDirection="column">
              <Text color="greenBright" bold>🎉 Challenge complete!</Text>
              <Text color="green">All 10 tasks solved. Show this screen to your mentor.</Text>
            </Box>
          ) : (
            <TaskDetail
              task={selectedTask}
              status={selectedStatus}
              attempts={progress.attempts[selectedTask.id] ?? 0}
              hintIndex={hintIndex}
            />
          )}
        </Box>
      </Box>
      {feedback.kind && <Feedback kind={feedback.kind} message={feedback.msg} />}
      {mode === 'answer' && (
        <AnswerInput
          prompt={`Answer → Task ${selectedTask.index}: `}
          onSubmit={handleAnswer}
          onCancel={() => setMode('list')}
        />
      )}
      <HelpBar />
    </Box>
  );
}
