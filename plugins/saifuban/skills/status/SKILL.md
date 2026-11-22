---
name: status
description: Show how much Claude Code (or another agent) has spent today through Saifuban and how much of the daily budget is left. Use when the user asks things like "how much did I spend today", "残りいくら", "今日いくら使った", or wants to change the Saifuban budget.
allowed-tools: Bash(npx:*), Bash(npx.cmd:*)
---

1. Run (on Windows use `npx.cmd`):

   ```
   npx -y saifuban status
   ```

2. Answer in one or two short lines in the user's language: spent today, left today, the daily budget, and when it resets.
3. If the user wants a different budget: budgets can only be changed on the Saifuban dashboard (https://ut181749ut.github.io/saifuban/), not from here. That's on purpose, so an agent can't raise its own cap. Tell them that in one line.
4. If it says Saifuban isn't set up on this computer, offer `/saifuban:setup`.
