You are executing the Rain audit and hardening program in D:\Rain.

1. Read `audit/prompts/rain-orchestrator.xml` in full. It is your only instruction set; follow it literally.
2. Read `AGENTS.md` and `audit/00-inventory.md`. Do not re-run the Phase 0 commands; their results are in the inventory.
3. If `audit/STATE.md` exists, follow `<resume_protocol>`. Otherwise start at task T0.1.
4. Run tasks in order. Commit after every task per `<commit_protocol>`. Push after every phase.
5. Keep chat output to one line per finished task: "T1.3 done abc1234". Put details in the audit files.
6. Stop only where a task says STOP, or when all phases are done. Then print the final 5-line summary.
