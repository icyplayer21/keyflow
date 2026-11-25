# Keyflow export format

Settings ▸ Data & Privacy ▸ Export… writes one UTF-8 JSON file. Keys are
sorted, dates are ISO 8601 (UTC) and numbers are plain JSON numbers.
Source: `Sources/Keyflow/DataExport.swift`.

## Schema version 1

| Key | Type | Meaning |
| --- | --- | --- |
| `schemaVersion` | integer | `1`. Raised whenever a field is removed or changes meaning. Added fields don't raise it. |
| `app` | string | `"Keyflow"` |
| `appVersion` | string | `CFBundleShortVersionString (CFBundleVersion)` of the app that wrote the file |
| `exportedAt` | date | When the file was written |
| `sessions` | array | Practice and Test sessions, oldest first |
| `lessons` | array | Learn ▸ Lessons rounds and skips |
| `fingerFocus` | array | Learn ▸ Finger Focus rounds |
| `fingerChecks` | array | Finger Focus checks (assessments) |
| `typingMechanics` | array | Learn ▸ Typing Mechanics rounds |
| `keyRepetition` | array | Learn ▸ Key Repetition sessions (added in a later build; absent from older exports) |
| `dailyFlow` | array | Learn ▸ Daily Flow finished passages (added in a later build; absent from older exports) |

### `sessions[]`

`id` (UUID), `date`, `kind` (`test`, or `practice.<mode>`), `timeLimitSeconds`,
`elapsedSeconds`, `netWPM`, `rawWPM`, `accuracy` (0–1), `consistency` (0–1 or
absent), `keystrokes`, `correctKeystrokes` and `backspaces`.

The passage, the typed text and the keystroke log are **not** exported. Custom
Text can hold anything the user pasted, so a session export carries numbers
only.

### `lessons[]`

`id`, `date`, `category` (for example `homeRow`), `stage` (an integer), `kind`
(`round` or `skip`) and `result`, which is absent for a skip.

### `fingerFocus[]`

`id`, `date`, `target` (a finger), `level` (an integer) and `result`.

### `fingerChecks[]`

`id`, `date`, `target` and `result` (a `FingerAssessmentResult`, as stored).

### `typingMechanics[]`

`id`, `date`, `drill` (for example `labShiftOnly`) and `result` (a
`MechanicsRoundResult`, as stored, including technique counts and timing
summaries).

### `keyRepetition[]`

`id`, `date`, `key` (a lower-case letter), `goal` (the repetitions chosen),
`mode` (`continuous` or `returnToHome`), `correct`, `incorrect`, `accuracy`
(`correct ÷ (correct + incorrect)`, 0–1) and `durationSeconds` (from the first
counted press, without paused time). Only completed sessions are saved; there
is no WPM for single-key repetition.

### `dailyFlow[]`

One entry per finished passage: `id`, `date`, `sessionID` (shared by the
passages of one session), `segment` (`warmUp`, `weakKeys` or `realText`),
`plannedMinutes`, `activeSeconds` (gaps between key presses, each counted up to
5 seconds), `hints` (positions where the next key was shown after a pause) and
`result` (a `RoundResult`). A hint says Keyflow showed a key; it does not say
whether the user looked at the keyboard.

A Learn `result` is the stored value with its own field names. A
`RoundResult` holds `text` (the generated exercise, never user-supplied),
`accuracy`, `keystrokes`, `correctKeystrokes`, `backspaces`, `duration`
(seconds), and per-key and per-pair `{attempts, errors}` counts.

## Not included

- Preferences. The export holds training data only.
- Keystroke logs and the text typed in Practice and Test.
