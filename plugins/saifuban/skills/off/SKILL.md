---
name: off
description: Stop routing Claude Code through Saifuban and put ~/.claude/settings.json back the way it was. Use when the user says things like "turn off Saifuban", "uninstall saifuban", "財布番やめたい", "財布番を外して", "元に戻して".
allowed-tools: Bash(npx:*), Bash(npx.cmd:*)
---

1. Run (on Windows use `npx.cmd`):

   ```
   npx -y saifuban off
   ```

2. Tell the user in one or two short lines, in their language, what it said: Saifuban was removed from Claude Code's settings, and a new Claude Code session will talk to Anthropic directly. Their agent and budget are kept on the dashboard, and running `/saifuban:setup` turns it back on.
3. If they also want the plugin itself gone, tell them to run `/plugin uninstall saifuban`.
