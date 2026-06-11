# TODO

## Bugs

## Features

## Tasks

## Completed
- ~~**[B01] [P1] `/hv-capture` Step 7 auto-dispatches `/hv-brainstorm` on `autonomy=auto`, conflating capture with planning.** Capture should be pure intake; auto-invoking brainstorm pulls the user into design exploration mid-brain-dump. Worse, the escalation is inverted: `auto` proactively brainstorms, `loop` skips entirely. Fix: Step 7 prints the nudge line in all modes (off/auto/loop) and never invokes the Skill tool. Move autonomous advancement to `/hv-next` where "advance without asking" semantics belong. Related: [F01], [F03]