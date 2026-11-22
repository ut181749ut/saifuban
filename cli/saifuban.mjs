#!/usr/bin/env node
// Saifuban setup in one command:  npx saifuban
// (Windows PowerShell: npx.cmd saifuban)
// Creates (or reuses) your Saifuban account, makes an agent with a daily budget,
// optionally stores your provider API key, and prints the two lines to set.
// No dependencies. Talks only to the Saifuban API.
import { createInterface } from "node:readline";
import { existsSync, mkdirSync, readFileSync, writeFileSync, copyFileSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { tmpdir } from "node:os";
import { fileURLToPath } from "node:url";
import { spawnSync } from "node:child_process";

const PROJECT = "https://zrphnuvrsldcycxtdftv.supabase.co/functions/v1";
const API = process.env.SAIFUBAN_API || PROJECT + "/saifuban-app";
const SITE = "https://ut181749ut.github.io/saifuban/";
// APIキー中継(Cloudflare 経由。長い応答も途中で切れない)
// セルフホスト: SAIFUBAN_API(自分の saifuban-app の住所)と SAIFUBAN_RELAY(自分の Worker の /proxy、なければ Supabase 直の中継)
const RELAY = process.env.SAIFUBAN_RELAY ||
  (process.env.SAIFUBAN_API ? process.env.SAIFUBAN_API.replace(/\/saifuban-app\/?$/, "/saifuban-proxy") : "https://saifuban.saifuban-app.workers.dev/proxy");
const PROVIDERS = {
  // Claude Code は ANTHROPIC_API_KEY だと初回に「このキーを使う?」と聞き、既定が「いいえ」。Enter で断ると以後黙って無視される。
  // ANTHROPIC_AUTH_TOKEN なら聞かれずにすぐ使われる(Anthropic SDK もこの変数を読む)
  anthropic: { label: "Anthropic (Claude Code, Anthropic SDK)", env: "ANTHROPIC", keyVar: "ANTHROPIC_AUTH_TOKEN", base: "/anthropic", keyHint: "sk-ant-…", name: "Claude Code" },
  openai: { label: "OpenAI (OpenAI SDK, LangChain, CrewAI…)", env: "OPENAI", keyVar: "OPENAI_API_KEY", base: "/openai/v1", keyHint: "sk-…", name: "OpenAI agent" },
  openrouter: { label: "OpenRouter (one key, many models)", env: "OPENAI", keyVar: "OPENAI_API_KEY", base: "/openrouter/v1", keyHint: "sk-or-…", name: "OpenRouter agent" },
  // Gemini は無料のAPIキーがあるので、お金をかけずに試せる(OpenAI と同じ書き方で呼べる)
  google: { label: "Google Gemini (free API key: aistudio.google.com/apikey)", env: "OPENAI", keyVar: "OPENAI_API_KEY", base: "/google/v1beta/openai", keyHint: "AIza…", name: "Gemini agent" },
};
// 手元の環境にもう入っている本物のキー(あれば、貼らずに預けられる)
const ENV_KEYS = {
  anthropic: [["ANTHROPIC_API_KEY", /^sk-ant-/]],
  openai: [["OPENAI_API_KEY", /^sk-(?!or-|ant-)/]],
  openrouter: [["OPENROUTER_API_KEY", /^sk-or-/], ["OPENAI_API_KEY", /^sk-or-/]],
  google: [["GEMINI_API_KEY", /^AIza/], ["GOOGLE_API_KEY", /^AIza/]],
};
// 動作確認(無料): 本物のキーで、モデル一覧を中継経由で取ってみる
const TEST = {
  anthropic: (k) => ({ url: "/anthropic/v1/models", headers: { "x-api-key": k, "anthropic-version": "2023-06-01" } }),
  openai: (k) => ({ url: "/openai/v1/models", headers: { authorization: "Bearer " + k } }),
  openrouter: (k) => ({ url: "/openrouter/v1/key", headers: { authorization: "Bearer " + k } }),
  google: (k) => ({ url: "/google/v1beta/models", headers: { "x-goog-api-key": k } }),
};
// この端末に保存するのは、AIのキー(sbk_)と、残高表示に使う住所だけ。
// アカウントの合言葉(sbo_)は保存しない: 同じパソコンで動くAIが読めてしまい、自分の予算を上げられてしまうから
const CONF_DIR = join(homedir(), ".saifuban");
const CONF = join(CONF_DIR, "config.json");
const readConf = () => { try { return JSON.parse(readFileSync(CONF, "utf8")); } catch { return {}; } };
const writeConf = (c) => { try { mkdirSync(CONF_DIR, { recursive: true }); writeFileSync(CONF, JSON.stringify(c, null, 2) + "\n", { mode: 0o600 }); return true; } catch { return false; } };

const args = process.argv.slice(2);

// npx は一度ダウンロードしたものを使い回すので、古い版が動くことがある。
// 起動時に GitHub の最新版と比べ、違っていれば最新版を動かす(この CLI は1ファイルで依存なし)
async function runLatestIfOutdated() {
  if (process.env.SAIFUBAN_NO_UPDATE) return;
  try {
    const ctl = new AbortController();
    const t = setTimeout(() => ctl.abort(), 4000);
    const r = await fetch(process.env.SAIFUBAN_CLI_URL || "https://raw.githubusercontent.com/ut181749ut/saifuban/main/cli/saifuban.mjs", { signal: ctl.signal });
    clearTimeout(t);
    if (!r.ok) return;
    const latest = await r.text();
    if (!latest.startsWith("#!/usr/bin/env node") || !latest.includes("Saifuban setup in one command")) return;
    const mine = readFileSync(fileURLToPath(import.meta.url), "utf8");
    if (latest.replace(/\r\n/g, "\n") === mine.replace(/\r\n/g, "\n")) return;
    const f = join(tmpdir(), "saifuban-latest.mjs");
    writeFileSync(f, latest);
    const res = spawnSync(process.execPath, [f, ...args], { stdio: "inherit", env: { ...process.env, SAIFUBAN_NO_UPDATE: "1" } });
    process.exit(res.status ?? 1);
  } catch { /* オフラインなどのときは、手元の版でそのまま進む */ }
}
await runLatestIfOutdated();
const flag = (name) => { const i = args.indexOf("--" + name); return i >= 0 ? args[i + 1] : undefined; };
if (args.includes("--help") || args.includes("-h")) {
  console.log(`Saifuban: a hard daily cap on your AI agent's API bill.

Usage: npx saifuban [--budget 7] [--provider anthropic|openai|openrouter|google] [--yes]

  --budget    daily budget (default $7, or ¥1000 in Japan)
  --currency  USD or JPY (default: JPY in Japan, USD elsewhere)
  --provider  which API your agent uses (default anthropic)
  --name      a name for the agent (default: "Claude Code", "OpenAI agent", …)
  --yes       don't ask: use the API key already in your environment and save to ~/.claude/settings.json
  --open      open the dashboard in your browser at the end (already signed in)
  --new       make a new account even if this computer already has one
  --login     use an account you already have (asks for its sbo_ passphrase)

  status      show today's spending and what's left:  npx … status
  off         stop using Saifuban in Claude Code (puts settings.json back; run setup again to turn it on)

Your account is remembered in ~/.saifuban/config.json. You can also pass a passphrase
in SAIFUBAN_OWNER_KEY and a provider API key in SAIFUBAN_PROVIDER_KEY.`);
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

// 今日の状況(AIのキーで読める範囲だけ。予算を変えるのは管理画面から)
async function status(c) {
  const r = await fetch((c.api || PROJECT + "/saifuban") + "/budget", { headers: { authorization: "Bearer " + c.agent.key }, signal: AbortSignal.timeout(10000) });
  const j = await r.json().catch(() => ({}));
  if (!r.ok || j.error) throw new Error("couldn't read the budget (" + (j.error || r.status) + ")");
  const usd = j.currency === "USD";
  const m = (k) => usd ? "$" + Number(j[k + "_usd"] ?? 0).toFixed(2) : "¥" + Math.round(Number(j[k + "_jpy"] ?? 0)).toLocaleString("en-US");
  console.log(bold(`${j.agent || c.agent.name}:`) + ` ${m("spent_today")} used today, ${m("remaining_today")} left of ${m("daily_budget")} (resets ${String(j.budget_resets_at || "at midnight").replace(/^midnight/, "at midnight")}).`);
  if (j.weekly_budget_jpy) console.log(`  This week: ${m("used_this_week")} of ${m("weekly_budget")}.`);
  if (j.monthly_budget_jpy) console.log(`  This month: ${m("used_this_month")} of ${m("monthly_budget")}.`);
  console.log(dim(`\nTo change the budget, open ${SITE} (it's where you approve payments too).`));
}

// Claude Code の画面の下に出す一行(1分ごとに読み直す。速く終わるよう、npx を通さない小さなファイル)
const STATUS_SCRIPT = join(CONF_DIR, "statusline.mjs");
function writeStatusScript() {
  const code = `// Saifuban status line for Claude Code: shows the money left today. Made by the Saifuban setup command.
import { readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";
import { homedir } from "node:os";
const dir = join(homedir(), ".saifuban"), cache = join(dir, "status-cache.json");
try { process.stdin.resume(); process.stdin.on("data", () => {}); } catch {}
const show = (j) => {
  const usd = j.currency === "USD";
  const m = (k) => usd ? "$" + Number(j[k + "_usd"] ?? 0).toFixed(2) : "¥" + Math.round(Number(j[k + "_jpy"] ?? 0)).toLocaleString("en-US");
  const ja = !usd;
  console.log((ja ? "財布番 残り " : "Saifuban ") + m("remaining_today") + (ja ? " / " : " left of ") + m("daily_budget"));
  process.exit(0);
};
let c = {}; try { c = JSON.parse(readFileSync(cache, "utf8")); } catch {}
if (c.at && Date.now() - c.at < 60000 && c.data) show(c.data);
try {
  const conf = JSON.parse(readFileSync(join(dir, "config.json"), "utf8"));
  const r = await fetch(conf.api + "/budget", { headers: { authorization: "Bearer " + conf.agent.key }, signal: AbortSignal.timeout(2500) });
  const j = await r.json();
  if (!j.error) { try { writeFileSync(cache, JSON.stringify({ at: Date.now(), data: j })); } catch {} show(j); }
} catch {}
if (c.data) show(c.data);
console.log("Saifuban");
`;
  try { mkdirSync(CONF_DIR, { recursive: true }); writeFileSync(STATUS_SCRIPT, code); return true; } catch { return false; }
}

// Claude Code の設定ファイル
const claudeSettings = () => join(process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude"), "settings.json");
const readJson = (f) => { try { const t = readFileSync(f, "utf8"); return t.trim() ? JSON.parse(t) : {}; } catch { return null; } };
const isOurs = {
  base: (v) => typeof v === "string" && /saifuban/i.test(v),
  token: (v) => typeof v === "string" && v.startsWith("sbk_"),
  line: (s) => !!s && typeof s.command === "string" && s.command.includes(".saifuban") && s.command.includes("statusline.mjs"),
};

// やめる: Claude Code の設定から財布番の分だけ外す(ほかの設定はそのまま)。AIや予算は消さない
function turnOff() {
  const file = claudeSettings();
  const cur = existsSync(file) ? readJson(file) : {};
  if (cur === null) throw new Error(`couldn't read ${file} (is it valid JSON?)`);
  const removed = [];
  const env = cur.env || {};
  if (isOurs.base(env.ANTHROPIC_BASE_URL)) { delete env.ANTHROPIC_BASE_URL; removed.push("ANTHROPIC_BASE_URL"); }
  if (isOurs.token(env.ANTHROPIC_AUTH_TOKEN)) { delete env.ANTHROPIC_AUTH_TOKEN; removed.push("ANTHROPIC_AUTH_TOKEN"); }
  if (isOurs.token(env.ANTHROPIC_API_KEY)) { delete env.ANTHROPIC_API_KEY; removed.push("ANTHROPIC_API_KEY"); }
  // 設定のときに外した本物のキーがバックアップにあれば戻す
  const bak = readJson(file + ".bak-saifuban");
  const real = bak && bak.env && bak.env.ANTHROPIC_API_KEY;
  let restored = false;
  if (real && !isOurs.token(real) && !env.ANTHROPIC_API_KEY) { env.ANTHROPIC_API_KEY = real; restored = true; }
  if (Object.keys(env).length) cur.env = env; else delete cur.env;
  if (isOurs.line(cur.statusLine)) { delete cur.statusLine; removed.push("statusLine"); }
  if (removed.length || restored) writeFileSync(file, JSON.stringify(cur, null, 2) + "\n");
  const c = readConf();
  if (c.agent) { c.off = true; writeConf(c); }
  if (!removed.length && !restored) console.log("Saifuban wasn't in " + file + ", so nothing changed.");
  else {
    console.log(bold("Saifuban is off.") + ` Removed ${removed.join(", ")} from ${file}` + (restored ? " and put your ANTHROPIC_API_KEY back." : "."));
    console.log("Start a new Claude Code session and it talks to Anthropic directly again.");
  }
  console.log(dim("Your agent and budget are kept. Run the setup command again to turn it back on, or delete the agent on " + SITE + "\n"));
}

// また使う: 前に作ったAIのキーで Claude Code の設定を書き直す
function turnOn(c) {
  const file = claudeSettings();
  const cur = existsSync(file) ? readJson(file) : {};
  if (cur === null) throw new Error(`couldn't read ${file} (is it valid JSON?)`);
  if (existsSync(file)) copyFileSync(file, file + ".bak-saifuban");
  else mkdirSync(join(file, ".."), { recursive: true });
  const env = { ...(cur.env || {}), ANTHROPIC_BASE_URL: (c.relay || RELAY) + PROVIDERS.anthropic.base, ANTHROPIC_AUTH_TOKEN: c.agent.key };
  if (env.ANTHROPIC_API_KEY && !isOurs.token(env.ANTHROPIC_API_KEY)) delete env.ANTHROPIC_API_KEY;
  cur.env = env;
  if (!cur.statusLine && writeStatusScript()) cur.statusLine = { type: "command", command: `node "${STATUS_SCRIPT}"` };
  writeFileSync(file, JSON.stringify(cur, null, 2) + "\n");
  delete c.off; writeConf(c);
  console.log(bold("Saifuban is back on") + ` for "${c.agent.name}". Start a new Claude Code session.\n`);
}

async function main() {
  if (args[0] === "off") { turnOff(); rl.close(); return; }
  // 今日の状況だけ見る: npx … status
  if (args[0] === "status") {
    const c = readConf();
    if (!c.agent || !c.agent.key) { console.log("Saifuban isn't set up on this computer yet. Run the setup command without \"status\"."); rl.close(); return; }
    await status(c); rl.close(); return;
  }
  console.log(bold("\nSaifuban") + " — a hard daily cap on your AI agent's API bill\n");

  // 1. account
  // 貼り付けたときに前後の空白・引用符・端末の制御文字が混ざっても、合言葉の部分だけを取り出す
  const pick = (v) => (String(v || "").match(/sbo_[0-9a-f]{48}/i)?.[0] || "").toLowerCase();
  const YES = args.includes("--yes") || args.includes("-y");
  let owner = pick(process.env.SAIFUBAN_OWNER_KEY);
  if (!owner && process.env.SAIFUBAN_OWNER_KEY) throw new Error("SAIFUBAN_OWNER_KEY doesn't look like a Saifuban passphrase (sbo_ + 48 hex characters).");
  const conf = readConf();
  if (conf.owner_key) { delete conf.owner_key; writeConf(conf); } // 以前の版が保存した合言葉は消す
  // もう設定済みなら、新しく作らずに今日の状況を見せる(--new で別のAIを作る)
  if (!owner && conf.agent && conf.agent.key && !args.includes("--new") && !args.includes("--login")) {
    if (conf.off && (conf.agent.provider || "anthropic") === "anthropic") { turnOn(conf); await status(conf).catch(() => {}); rl.close(); return; }
    console.log(dim(`This computer is already set up (agent "${conf.agent.name}"). Add --new to make another agent, or --login to use a passphrase.\n`));
    await status(conf);
    rl.close();
    return;
  }
  // 合言葉は、--login を付けたときだけ聞く(初めての人は何も聞かずに新しく作る)
  for (let tries = 0; !owner && !YES && args.includes("--login") && tries < 3; tries++) {
    const a = await ask(tries === 0
      ? "Already have a Saifuban passphrase (sbo_…)? Paste it (it stays hidden), or press Enter to create a new account: "
      : "Paste the passphrase again (sbo_ + 48 letters/numbers), or press Enter to create a new account: ", true);
    if (!a.trim()) break;
    owner = pick(a);
    if (!owner) console.log(dim(`  That wasn't a passphrase (got ${a.trim().length} characters, expected 52 starting with sbo_). You can copy it from Settings on ${SITE}`));
  }
  if (!owner && closed) { /* 入力が終わった(パイプ)ときは新規作成に進む */ }
  let created = false;
  if (!owner) {
    const r = await call("signup");
    owner = r.owner_key;
    created = true;
    call("track", { event: "signup", src: "cli", lang: "en" }).catch(() => {});
  }
  const dash = await call("dashboard", {}, owner);

  // 1日の予算は、この端末の時間帯の0時で区切る(まだ決めていないアカウントだけ)
  const tz = (() => { try { return Intl.DateTimeFormat().resolvedOptions().timeZone || ""; } catch { return ""; } })();
  const tzr = tz ? await call("set_tz", { tz, auto: true }, owner).catch(() => null) : null;

  // 表示の通貨: 日本の人は円、それ以外はドル(新しいアカウントだけ自動で決める。--currency で指定も可)
  const rate = Number(dash && dash.usd_jpy) || 155;
  const locale = (() => { try { return Intl.DateTimeFormat().resolvedOptions().locale || ""; } catch { return ""; } })();
  let cur = String(flag("currency") || "").toUpperCase();
  if (cur !== "USD" && cur !== "JPY") cur = created ? (/^ja/i.test(locale) || tz === "Asia/Tokyo" ? "JPY" : "USD") : (dash && dash.currency === "USD" ? "USD" : "JPY");
  if (cur !== (dash && dash.currency) && (created || flag("currency"))) await call("set_currency", { currency: cur }, owner).catch(() => {});
  const money = (jpy) => cur === "USD" ? "$" + (jpy / rate).toFixed(2) : "¥" + Math.round(jpy).toLocaleString("en-US");

  // 2. agent(予算は内部では円で持つ)
  const input = flag("budget") || (YES ? "" : await ask(cur === "USD" ? "Daily budget in USD [7]: " : "Daily budget in yen [1000 ≈ $6.50]: "));
  const amount = Number(input || (cur === "USD" ? 7 : 1000));
  if (!Number.isFinite(amount) || amount <= 0) throw new Error("The budget must be a positive number.");
  const budget = Math.max(1, Math.round(cur === "USD" ? amount * rate : amount));
  let provider = flag("provider");
  // 手元にキーが1種類だけあれば、どのAPIか聞かずに決める
  if (!provider) {
    const have = Object.keys(ENV_KEYS).filter((p) => ENV_KEYS[p].some(([v, re]) => re.test(String(process.env[v] || "").trim())));
    if (have.length === 1) { provider = have[0]; console.log(dim(`Using ${PROVIDERS[provider].label.split(" (")[0]} (found your key in the environment).`)); }
  }
  if (!provider && YES) provider = "anthropic";
  if (!provider) {
    console.log("\nWhich API does your agent use?");
    const keys = Object.keys(PROVIDERS);
    keys.forEach((k, i) => console.log(`  ${i + 1}. ${PROVIDERS[k].label}`));
    const pick = await ask(`Choose 1-${keys.length} [1]: `);
    provider = keys[(Number(pick) || 1) - 1] || "anthropic";
  }
  if (!PROVIDERS[provider]) throw new Error("Unknown provider: " + provider);
  const P = PROVIDERS[provider];
  const name = (flag("name") || P.name).slice(0, 60);
  const ag = await call("create_agent", { name, per_tx: budget, daily: budget, auto: Math.min(300, budget), merchants: [] }, owner);
  call("track", { event: "agent_created", src: "cli", lang: "en" }).catch(() => {});
  const confNew = { ...readConf(), agent: { id: ag.id, key: ag.agent_key, name, provider }, api: API.replace(/\/saifuban-app\/?$/, "/saifuban"), relay: RELAY };
  delete confNew.off;
  writeConf(confNew);

  // 3. provider key (stored encrypted; the agent never sees it)
  let pkey = process.env.SAIFUBAN_PROVIDER_KEY || "";
  let settingsOk = false; // 1回の確認で、キーを預けるのと Claude Code の設定をまとめて済ませる
  if (!pkey) {
    // 環境変数に本物のキーがあれば、それを使うか聞く(貼る手間をなくす)
    const found = (ENV_KEYS[provider] || []).map(([v, re]) => [v, String(process.env[v] || "").trim(), re]).find(([, val, re]) => re.test(val));
    if (found) {
      const [v, val] = found;
      const also = provider === "anthropic" && !args.includes("--no-settings") ? " and point Claude Code at Saifuban" : "";
      const ok = YES || !(await ask(`\nFound your key in ${v} (${val.slice(0, 7)}…${val.slice(-4)}). Store it in Saifuban (encrypted)${also}? [Y/n]: `)).toLowerCase().startsWith("n");
      if (ok) { pkey = val; if (also) settingsOk = true; }
    }
  }
  if (!pkey && !YES) pkey = await ask(`\nYour real ${provider} API key (${P.keyHint}), stored encrypted in Saifuban. Press Enter to add it later on the website: `, true);
  if (pkey) {
    await call("set_provider_key", { provider, key: pkey }, owner);
    call("track", { event: "key_stored", src: "cli", lang: "en" }).catch(() => {});
  }
  // Claude Code: ~/.claude/settings.json の env に書けば、新しいターミナルでも(バックグラウンドのエージェントでも)ずっと効く
  let savedTo = "", statusLine = "";
  // キーを預けていないのに Claude Code を中継に向けると、全部の呼び出しが失敗する(サブスクで使っている人も止まる)ので、そのときは書かない
  if (provider === "anthropic" && !pkey && !args.includes("--no-settings")) {
    console.log(dim("\nNo Anthropic API key was stored, so Claude Code's settings were left as they are. Add the key on the dashboard, then run this command again."));
  }
  if (provider === "anthropic" && pkey && !args.includes("--no-settings")) {
    const dir = process.env.CLAUDE_CONFIG_DIR || join(homedir(), ".claude");
    const file = join(dir, "settings.json");
    const yes = YES || settingsOk ? "y" : (await ask(`\nSave it to ${file} so Claude Code always uses it (new terminals too)? [Y/n]: `)).toLowerCase();
    if (!yes.startsWith("n")) {
      try {
        let cur = {};
        if (existsSync(file)) {
          const txt = readFileSync(file, "utf8");
          cur = txt.trim() ? JSON.parse(txt) : {};
          copyFileSync(file, file + ".bak-saifuban");
        } else mkdirSync(dir, { recursive: true });
        cur.env = { ...(cur.env || {}), ANTHROPIC_BASE_URL: RELAY + P.base, ANTHROPIC_AUTH_TOKEN: ag.agent_key };
        // 画面の下に今日の残りを出す(すでに自分のステータスラインがある人は、そのままにする)
        if (!cur.statusLine && writeStatusScript()) {
          cur.statusLine = { type: "command", command: `node "${STATUS_SCRIPT}"` };
          statusLine = STATUS_SCRIPT;
        }
        // 本物のキーが残っていると、そちらが先に使われて中継で断られる
        if (cur.env.ANTHROPIC_API_KEY && !String(cur.env.ANTHROPIC_API_KEY).startsWith("sbk_")) {
          delete cur.env.ANTHROPIC_API_KEY;
          console.log(dim("  Removed your real ANTHROPIC_API_KEY from that file's env (it's still in the backup), so it can't bypass the cap."));
        }
        writeFileSync(file, JSON.stringify(cur, null, 2) + "\n");
        savedTo = file;
      } catch (e) {
        console.log(dim(`  Couldn't update ${file} (${e.message}). Set the lines below by hand instead.`));
      }
    }
  }
  rl.close();

  // 4. 動作確認(モデル一覧を中継経由で取る。生成はしないので無料)
  let tested = "";
  if (pkey && TEST[provider]) {
    try {
      const t = TEST[provider](ag.agent_key);
      const r = await fetch(RELAY + t.url, { headers: t.headers, signal: AbortSignal.timeout(15000) });
      if (r.ok) tested = "ok";
      else {
        let msg = ""; try { const j = await r.json(); msg = j?.error?.message || j?.message || ""; } catch { /* */ }
        tested = `${r.status}${msg ? ": " + String(msg).slice(0, 200) : ""}`;
      }
    } catch (e) { tested = "couldn't reach the proxy (" + (e && e.message || e) + ")"; }
  }

  // 5. result
  console.log("\n" + bold("Done.") + ` Agent "${name}" can spend up to ${money(budget)} a day` +
    (tzr && tzr.tz ? ` (resets at midnight, ${tzr.tz}).\n` : ".\n"));
  if (tested === "ok") console.log(bold("✓ Checked:") + ` your ${provider} key works through Saifuban.\n`);
  else if (tested) console.log(bold("✗ Check failed") + ` (${tested}). Your key may be wrong; you can replace it on the dashboard.\n`);

  const KV = P.keyVar;
  if (savedTo) {
    console.log(bold("Saved") + ` to ${savedTo}. Start a new Claude Code session and it goes through Saifuban.`);
    console.log(dim(`  (The old file is kept as settings.json.bak-saifuban. To stop using Saifuban, run this command with "off".)\n`));
    console.log("For other tools (Anthropic SDK, scripts), set these two lines in the shell:\n");
  } else {
    console.log(bold("Set these two lines") + " in the shell where your agent runs:\n");
  }
  if (process.platform === "win32") {
    // Windows: PowerShell と コマンドプロンプト の両方の書き方を出す
    console.log(dim("  PowerShell:"));
    console.log(`  $env:${P.env}_BASE_URL="${RELAY}${P.base}"`);
    console.log(`  $env:${KV}="${ag.agent_key}"\n`);
    console.log(dim("  Command Prompt (cmd):"));
    console.log(`  set ${P.env}_BASE_URL=${RELAY}${P.base}`);
    console.log(`  set ${KV}=${ag.agent_key}\n`);
  } else {
    console.log(`  export ${P.env}_BASE_URL="${RELAY}${P.base}"`);
    console.log(`  export ${KV}="${ag.agent_key}"\n`);
  }
  if (provider === "anthropic") console.log(dim("If ANTHROPIC_API_KEY (your real key) is also set in that shell, unset it, or it gets used instead.\n"));
  if (!pkey) console.log(dim(`Add your ${provider} API key in Settings on the dashboard before the first call.\n`));
  // 管理画面: ログイン済みで開くリンク(合言葉は # の後ろなので、サーバーには送られない)
  const link = SITE + "#k=" + owner;
  console.log(bold("Dashboard") + " (spending, budgets, approvals). This link signs you in, so keep it to yourself and bookmark the page after opening it:");
  console.log("  " + link + "\n");
  if (statusLine) console.log(dim(`Claude Code's status line now shows the money left today (${statusLine}).\n`));
  if (args.includes("--open")) {
    const cmd = process.platform === "win32" ? ["cmd", ["/c", "start", "", link]] : process.platform === "darwin" ? ["open", [link]] : ["xdg-open", [link]];
    try { spawnSync(cmd[0], cmd[1], { stdio: "ignore" }); } catch { /* */ }
  }
}

main().catch((e) => {
  rl.close();
  console.error("\nSaifuban setup failed: " + (e && e.message ? e.message : e));
  process.exit(1);
});
