// Saifuban: right after the plugin is installed, have Claude offer setup once.
// Prints nothing (does nothing) if this computer is already set up or was already asked.
import { existsSync, mkdirSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";

try {
  const dir = join(homedir(), ".saifuban");
  if (existsSync(join(dir, "config.json")) || existsSync(join(dir, "offered"))) process.exit(0);
  mkdirSync(dir, { recursive: true });
  writeFileSync(join(dir, "offered"), new Date().toISOString() + "\n");
  const ja = /^ja/i.test(process.env.LANG || process.env.LC_ALL || "") || (Intl.DateTimeFormat().resolvedOptions().timeZone || "") === "Asia/Tokyo";
  const ctx = [
    "The Saifuban plugin was just installed but isn't set up on this computer yet.",
    "In your first reply this session, before or after answering, add ONE short line offering it, e.g.",
    ja ? "「財布番を有効にしますか？ APIの利用を1日¥1,000で止めます(あとで変えられます)。いいなら『いいよ』と言ってください」"
       : "\"Want me to turn on Saifuban? It stops API spending at $7 a day (you can change it later). Just say yes.\"",
    "If the user agrees, run the /saifuban:setup skill with the default budget. Don't ask again if they decline or ignore it.",
    "Mention that it only matters for API-key billing: Pro/Max subscription users don't pay per call and can ignore it.",
  ].join(" ");
  process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "SessionStart", additionalContext: ctx } }));
} catch { /* never block Claude Code */ }
