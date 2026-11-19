#!/usr/bin/env node
// Saifuban setup in one command:  npx github:ut181749ut/saifuban
// Creates (or reuses) your Saifuban account, makes an agent with a daily budget,
// optionally stores your provider API key, and prints the two lines to set.
// No dependencies. Talks only to the Saifuban API.
import { createInterface } from "node:readline";

const PROJECT = "https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1";
const API = process.env.SAIFUBAN_API || PROJECT + "/saifuban-app";
const SITE = "https://ut181749ut.github.io/saifuban/";
// APIキー中継(Cloudflare 経由。長い応答も途中で切れない)
const RELAY = "https://saifuban.saifuban-app.workers.dev/proxy";
const PROVIDERS = {
  anthropic: { label: "Anthropic (Claude Code, Anthropic SDK)", env: "ANTHROPIC", base: "/anthropic", keyHint: "sk-ant-…" },
  openai: { label: "OpenAI (OpenAI SDK, LangChain, CrewAI…)", env: "OPENAI", base: "/openai/v1", keyHint: "sk-…" },
  openrouter: { label: "OpenRouter (one key, many models)", env: "OPENAI", base: "/openrouter/v1", keyHint: "sk-or-…" },
};

const args = process.argv.slice(2);
const flag = (name) => { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : undefined; };
if (args.includes("--help") || args.includes("-h")) {
  console.log(`Saifuban: a hard daily cap on your AI agent's API bill.

Usage: npx github:ut181749ut/saifuban [--budget 1000] [--provider anthropic|openai|openrouter] [--name "Claude Code"]

  --budget    daily budget in yen (default 1000, about $6.50)
  --provider  which API your agent uses (default anthropic)
  --name      a name for the agent (default "Claude Code")

Your existing Saifuban passphrase can be passed in SAIFUBAN_OWNER_KEY,
and your provider API key in SAIFUBAN_PROVIDER_KEY, to skip the prompts.`);
  process.exit(0);
}

const rl = createInterface({ input: process.stdin, output: process.stdout, terminal: !!process.stdin.isTTY });
// 入力を1行ずつためておき、質問のたびに取り出す(パイプで流し込んでも動くように)
const lines = [];
let waiting = null, closed = false, muted = false;
rl.on("line", (l) => { if (waiting) { const w = waiting; waiting = null; w(l); } else lines.push(l); });
rl.on("close", () => { closed = true; if (waiting) { const w = waiting; waiting = null; w(""); } });
const origWrite = rl._writeToOutput?.bind(rl);
if (origWrite) rl._writeToOutput = (s) => { if (!muted) origWrite(s); else if (s.includes("\n")) origWrite("\n"); };
const ask = (q, hidden = false) => new Promise((res) => {
  process.stdout.write(q);
  const done = (a) => { muted = false; if (!process.stdin.isTTY) process.stdout.write("\n"); res(String(a || "").trim()); };
  if (lines.length) return done(lines.shift());
  if (closed) return done("");
  muted = hidden && !!process.stdin.isTTY;
  waiting = done;
});

async function call(action, body = {}, owner) {
  const r = await fetch(API, {
    method: "POST",
    headers: { "content-type": "application/json", ...(owner ? { "x-owner-key": owner } : {}) },
    body: JSON.stringify({ action, ...body }),
  });
  let j = {};
  try { j = await r.json(); } catch { /* ignore */ }
  if (j.error) throw new Error(j.message || j.error);
  return j;
}

const bold = (s) => (process.stdout.isTTY ? `\x1b[1m${s}\x1b[0m` : s);
const dim = (s) => (process.stdout.isTTY ? `\x1b[2m${s}\x1b[0m` : s);

async function main() {
  console.log(bold("\nSaifuban") + " — a hard daily cap on your AI agent's API bill\n");

  // 1. account
  let owner = process.env.SAIFUBAN_OWNER_KEY || "";
  if (!owner) {
    const a = await ask("Already have a Saifuban passphrase (sbo_…)? Paste it, or press Enter to create a new account: ", true);
    owner = a;
  }
  if (owner && !/^sbo_[0-9a-f]{48}$/.test(owner)) throw new Error("That doesn't look like a Saifuban passphrase (sbo_ + 48 hex characters).");
  let created = false;
  if (!owner) {
    const r = await call("signup");
    owner = r.owner_key;
    created = true;
    call("track", { event: "signup", src: "cli", lang: "en" }).catch(() => {});
  } else {
    await call("dashboard", {}, owner);
  }
  // 1日の予算は、この端末の時間帯の0時で区切る(まだ決めていないアカウントだけ)
  const tz = (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || ""; } catch { return ""; } })();
  const tzr = tz ? await call("set_tz", { tz, auto: true }, owner).catch(() => null) : null;

  // 2. agent
  const budget = Math.round(Number(flag("budget") || (await ask("Daily budget in yen [1000 ≈ $6.50]: ")) || 1000));
  if (!Number.isFinite(budget) || budget < 1) throw new Error("The budget must be a positive number of yen.");
  const name = (flag("name") || "Claude Code").slice(0, 60);
  let provider = flag("provider");
  if (!provider) {
    console.log("\nWhich API does your agent use?");
    const keys = Object.keys(PROVIDERS);
    keys.forEach((k, i) => console.log(`  ${i + 1}. ${PROVIDERS[k].label}`));
    const pick = await ask("Choose 1-3 [1]: ");
    provider = keys[(Number(pick) || 1) - 1] || "anthropic";
  }
  if (!PROVIDERS[provider]) throw new Error("Unknown provider: " + provider);
  const P = PROVIDERS[provider];
  const ag = await call("create_agent", { name, per_tx: budget, daily: budget, auto: Math.min(300, budget), merchants: [] }, owner);
  call("track", { event: "agent_created", src: "cli", lang: "en" }).catch(() => {});

  // 3. provider key (stored encrypted; the agent never sees it)
  let pkey = process.env.SAIFUBAN_PROVIDER_KEY || "";
  if (!pkey) pkey = await ask(`\nYour real ${provider} API key (${P.keyHint}), stored encrypted in Saifuban. Press Enter to add it later on the website: `, true);
  if (pkey) {
    await call("set_provider_key", { provider, key: pkey }, owner);
    call("track", { event: "key_stored", src: "cli", lang: "en" }).catch(() => {});
  }
  rl.close();

  // 4. result
  console.log("\n" + bold("Done.") + ` Agent "${name}" can spend up to ¥${budget.toLocaleString("en-US")} a day` +
    (tzr && tzr.tz ? ` (resets at midnight, ${tzr.tz}).\n` : ".\n"));
  if (created) {
    console.log(bold("Your Saifuban passphrase") + " (your account; save it in a password manager, don't share it):");
    console.log("  " + owner + "\n");
  }
  console.log(bold("Set these two lines") + " in the shell where your agent runs:\n");
  console.log(`  export ${P.env}_BASE_URL="${RELAY}${P.base}"`);
  console.log(`  export ${P.env}_API_KEY="${ag.agent_key}"\n`);
  if (!pkey) console.log(dim(`Add your ${provider} API key in Settings on ${SITE} before the first call.\n`));
  console.log(`Watch spending, change the budget and approve payments at ${SITE}`);
  console.log(dim("(open it, choose \"I already use it on another device\" and paste the passphrase; you can add a passkey there too)\n"));
}

main().catch((e) => {
  rl.close();
  console.error("\nSaifuban setup failed: " + (e && e.message ? e.message : e));
  process.exit(1);
});
