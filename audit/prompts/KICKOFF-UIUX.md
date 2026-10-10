You are executing the Rain UI/UX level-up program. It runs next to the hardening program, in its own worktree.

1. Read `D:\Rain\audit\prompts\rain-uiux-orchestrator.xml` in full (after T0.1, read the copy in `D:\Rain-uiux\audit\prompts\`). It is your only instruction set; follow it literally.
2. Read `AGENTS.md` and `.ai/impeccable.md`. Do not re-derive anything listed under `<facts>`.
3. Never work in `D:\Rain` itself: the hardening program uses that checkout. All edits, tests and commits happen in `D:\Rain-uiux` on branch `ui/level-up`.
4. If `D:\Rain-uiux\audit\ui\STATE.md` exists, follow `<resume_protocol>`. Otherwise start at task T0.1.
5. Run tasks in order. Commit after every task per `<commit_protocol>`. Run `<sync_protocol>` at the start of every phase. Push after every phase.
6. Keep chat output to one line per finished task: "T2.3 done abc1234". Put details in `audit/ui/` files.
7. Stop only where a task says STOP, or when all phases are done. Then print the final 5-line summary.
