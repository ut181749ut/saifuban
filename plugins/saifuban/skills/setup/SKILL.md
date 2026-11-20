---
name: setup
description: Set up Saifuban so this machine's Claude Code (or another agent) goes through a proxy with a hard daily spending cap. Use when the user asks to cap, limit or budget their Claude Code / API spending, or runs /saifuban:setup.
argument-hint: "[daily budget, e.g. 10 or 1500yen] [anthropic|openai|openrouter|google]"
allowed-tools: Bash(npx:*), Bash(npx.cmd:*)
---

Set up Saifuban (an open-source proxy that stops API calls once a daily budget is used up) for the user.

1. Work out the daily budget and the provider from the arguments: $ARGUMENTS
   - A plain number is the budget in the user's currency. "yen" or "円" means JPY, "$" or "usd" means USD.
   - Provider defaults to `anthropic` (Claude Code). Use `google` if the user wants to try it for free with a Gemini key.
   - If no budget was given, don't ask: use the default ($7, or ¥1,000 for Japanese) and mention it can be changed on the dashboard. Don't ask the user anything before running the command.
2. Never ask the user to paste an API key into this chat. The setup command reads the key from the environment (ANTHROPIC_API_KEY, OPENAI_API_KEY, OPENROUTER_API_KEY, GEMINI_API_KEY) by itself, and if none is there the user can add it on the dashboard later.
3. Run this one command (on Windows use `npx.cmd` instead of `npx`):

   ```
   npx -y https://github.com/ut181749ut/saifuban/archive/refs/heads/main.tar.gz --yes --open --budget <BUDGET> --provider <PROVIDER>
   ```

   Always add `--currency`: `JPY` if the user said yen/円 or is writing in Japanese, otherwise `USD`. `--open` opens the user's dashboard in their browser, already signed in.
4. Report back in two or three short lines, in the user's language:
   - the daily budget and when it resets,
   - whether the key check passed (the output says "✓ Checked" or "✗ Check failed"),
   - for `anthropic`: that the cap applies from the next Claude Code session, so they should restart Claude Code; after that, the bottom of the screen shows the money left today (if the output says the status line was set up).
   Don't repeat the agent key (sbk_…), the dashboard link or the passphrase in chat; they're secrets and are already saved on this machine and opened in the browser.
   If the output says no Anthropic API key was stored, explain that Saifuban caps API-key usage, so Claude Code's settings were left alone. If they use Claude Code with a Pro/Max subscription, they aren't billed per call and don't need this; if they do use an API key, they can add it on the dashboard and run `/saifuban:setup` again.
   Also mention, in one line: the plugin also lets Claude ask Saifuban before buying anything; the first time that's used, Claude Code asks them to sign in to the `saifuban` server (run `/mcp`, pick saifuban, then Allow).
5. If the command fails, show the error line and suggest the manual route: https://github.com/ut181749ut/saifuban#readme
