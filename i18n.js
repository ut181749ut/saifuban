// 言語ボタンで英語に切り替え(最初は日本語。?lang=en / ?lang=ja でも切り替え可)
(function () {
  let lang = null;
  try {
    const q = new URLSearchParams(location.search).get("lang");
    if (q === "en" || q === "ja") { localStorage.setItem("saifuban.lang", q); lang = q; }
    else lang = localStorage.getItem("saifuban.lang");
  } catch (_) {}
  if (lang !== "en") lang = "ja";
  window.SAIFUBAN_LANG = lang;
  if (lang !== "en") return;
  document.documentElement.lang = "en";

  const D = {
    "AIの財布番": "Saifuban",
    "準備中…": "Starting…",
    "更新": "Refresh",
    "緊急停止": "Emergency stop",
    "停止を解除": "Resume all",
    "緊急停止中 — すべての支払いを止めています": "Emergency stop is on — all payments are blocked",
    "承認待ち": "Pending",
    "AIとルール": "AIs & rules",
    "履歴": "History",
    "設定": "Settings",
    "読み込み中…": "Loading…",
    "お金はここでは動きません · 15秒ごとに更新 ·": "No money moves here · refreshes every 15 s ·",
    "規約": "Terms",
    "プライバシー": "Privacy",
    "利用規約": "Terms of Service",
    "プライバシーポリシー": "Privacy Policy",
    "AIがお金を使う前に、あなたに聞きにくる": "Your AI asks you before it spends money",
    "API代の使いすぎ防止にも。": "Also stops runaway API bills.",
    "OpenAI・Anthropic・Google・OpenRouterのAPIキーを預けると、AIエージェントには代理のキーだけを渡し、1日の予算に達した時点でリクエストを止めます。": " Store your OpenAI, Anthropic, Google or OpenRouter key in Saifuban. Your agent only gets a proxy key, and requests stop once the daily budget is reached.",
    "AIに「1日いくらまで」「いくら以下なら聞かずにOK」を決めておくと、それを超える支払いはあなたのスマホに通知が届き、ボタン1つで承認・却下できます。": "Set a daily budget and an amount your AI can spend without asking. Anything above that comes to your phone as a notification, and you approve or reject it with one tap.",
    "この端末の合言葉が使えなくなっています": "The passphrase on this device no longer works",
    "もう一度入れ直すか、新しく始めてください。": "Enter it again, or start fresh.",
    "はじめる(無料)": "Start (free)",
    "はじめると": "By starting, you agree to the ",
    "と": " and ",
    "に同意したことになります。": ".",
    "別の端末ですでに使っている": "I already use it on another device",
    "合言葉(sbo_…)": "Passphrase (sbo_…)",
    "この端末で使う": "Use on this device",
    "あなたの合言葉ができました": "Here is your passphrase",
    "この合言葉が、あなたのアカウントそのものです。パスワードの代わりなので、メモアプリなどに保存してください。スマホを替えたときや、別の端末で開くときに使います。": "This passphrase is your account. It works like a password, so save it somewhere safe, such as a notes app. You'll need it when you change phones or open Saifuban on another device.",
    "合言葉をコピー": "Copy passphrase",
    "人に教えると、その人もあなたの財布番を操作できてしまいます。": "Anyone who has it can control your Saifuban, so don't share it.",
    "保存した。はじめる": "Saved it — let's go",
    "接続中": "Connected",
    "未接続": "Offline",
    "合言葉が無効です": "Invalid passphrase",
    "読み込めません": "Couldn't load",
    "もう一度": "Try again",
    "停止中": "Stopped",
    "稼働中": "Active",
    "あと使える": "left today",
    "つなぎ方": "How to connect",
    "削除されたAI": "Deleted AI",
    "(理由なし)": "(no reason given)",
    "却下する": "Reject",
    "承認する": "Approve",
    "承認": "OK",
    "いま判断が必要なものはありません。": "Nothing needs your decision right now.",
    "まだAIがつながっていません。": "No AI is connected yet.",
    "上の「AIをつなぐ」から始めてください。": "Start with \"Connect an AI\" above.",
    "まだ記録はありません": "No history yet",
    "自動": "Auto",
    "待ち": "Waiting",
    "却下": "Rejected",
    "失効": "Expired",
    "スマホに通知を受け取る": "Get notifications on your phone",
    "承認待ちを通知から承認できます": "Approve pending payments right from the notification",
    "オンにする": "Turn on",
    "通知を受け取るには": "To get notifications",
    "共有ボタン →「ホーム画面に追加」から開いてください": "Tap Share → \"Add to Home Screen\", then open it from there",
    "やり方": "How",
    "URLをコピーする": "Copy the URL",
    "URLをコピー": "Copy URL",
    "つなぐURLを用意する": "Get your connection URL",
    "前にコピーしたURLがあれば、それをそのまま使えます。手元にないときは、作り直してください(前のURLは使えなくなります)。": "If you still have the URL you copied before, use that. If not, make a new one (the old URL will stop working).",
    "URLを作り直す": "Make a new URL",
    "使っているAI": "Your AI",
    "その他": "Other",
    "Claudeのコネクタ画面を開く": "Open Claude's connector settings",
    "スマホのClaudeアプリでは追加できません。アプリが開いてしまうときは、SafariやChromeで claude.ai/settings/connectors を開いてください。有料プランが必要です。": "You can't add connectors in the Claude mobile app. If the app opens instead, go to claude.ai/settings/connectors in Safari or Chrome. Requires a paid plan.",
    "「カスタムコネクタを追加」を押して貼る": "Tap \"Add custom connector\" and paste",
    "名前は「財布番」、URLの欄にコピーしたURLを貼って「追加」。会話の「+」メニューで財布番がオンになっているかも確かめてください。": "Name it \"Saifuban\", paste the URL you copied, and tap Add. Then check that Saifuban is turned on in the \"+\" menu of your chat.",
    "ChatGPTの設定を開く": "Open ChatGPT settings",
    "ブラウザで開いてください。「アプリとコネクタ」→「詳細設定」で「開発者モード」をオンにします。有料プランが必要です。": "Open it in a browser. Go to \"Apps & Connectors\" → \"Advanced settings\" and turn on Developer mode. Requires a paid plan.",
    "「作成」からURLを貼る": "Tap \"Create\" and paste the URL",
    "名前は「財布番」、URLの欄にコピーしたURLを貼り、認証は「なし」で作成。会話の「+」メニューから財布番を選んで使います。": "Name it \"Saifuban\", paste the URL, set authentication to \"None\", and create it. Then pick Saifuban from the \"+\" menu in your chat.",
    "Museのチャットを開く": "Open a Muse chat",
    "スマホのMuseアプリでも大丈夫です。設定画面は使いません。": "The Muse mobile app works too. No settings screen needed.",
    "この文をMuseに送る": "Send this message to Muse",
    "文をコピー": "Copy message",
    "URLの部分は自分のURLに置き換えてください。認証を聞かれたら「なし」と答えます。": "Replace the URL part with your own URL. If Muse asks about authentication, answer \"none\".",
    "認証を聞かれたら「なし」と答えます。": "If Muse asks about authentication, answer \"none\".",
    "AIの設定でコネクタを探す": "Find the connector settings in your AI",
    "「コネクタ」「MCPサーバー」「ツール」「連携」などの名前の設定にあります。URLでつなぐMCP(リモートMCP)に対応したAIで使えます。Cursor・VS Codeなどは設定ファイルのMCPの欄に書きます。": "Look for a setting called \"Connectors\", \"MCP servers\", \"Tools\" or \"Integrations\". Any AI that supports remote MCP servers (added by URL) works. In Cursor, VS Code and similar tools, add it to the MCP section of the config file.",
    "URLを貼って保存する": "Paste the URL and save",
    "名前は「財布番」にしておくと分かりやすいです。認証はなしで大丈夫です。": "Naming it \"Saifuban\" makes it easy to find. No authentication is needed.",
    "つながったか試す": "Test the connection",
    "AIに「財布番で今日の残り予算を見て」と頼んでください。残りの金額が返ってくれば成功です。": "Ask your AI: \"Check my remaining budget for today with Saifuban.\" If it tells you an amount, you're connected.",
    "このURLはこの画面を閉じると二度と表示されません。人に見せないでください(なくしたら作り直せます)。": "This URL won't be shown again after you close this screen. Keep it private (you can make a new one if you lose it).",
    "閉じる": "Close",
    "パソコンでAPIキーごと見張りたい人向け": "For guarding API keys on a computer",
    "エージェントキー(「設定」でAPIキーを預けたときに使います):": "Agent key (used when you store an API key under Settings):",
    "キーをコピー": "Copy key",
    "AIをつなぐ": "Connect an AI",
    "別のAIをつなぐ": "Connect another AI",
    "+ 別のAIをつなぐ": "+ Connect another AI",
    "1日いくらまで使っていい?": "How much can it spend per day?",
    "いくら以下なら、あなたに聞かずに払っていい?": "Up to how much can it pay without asking you?",
    "毎回聞く": "Always ask",
    "それより高い支払いは、あなたのスマホに承認を聞きにきます。": "Anything above that will ask for your approval on your phone.",
    "名前(なくてもOK)": "Name (optional)",
    "例: 自宅のClaude": "e.g. Claude at home",
    "つなぐ": "Connect",
    "やめる": "Cancel",
    "スマホ通知": "Phone notifications",
    "オン": "On",
    "オフ": "Off",
    "ブロック中": "Blocked",
    "ホーム画面に追加が必要": "Add to Home Screen first",
    "非対応": "Not supported",
    "確認中…": "Checking…",
    "この端末に、承認待ちの通知が届きます。通知の「承認する」「却下」ボタンでそのまま判断できます(iPhoneでは通知を押すとこの画面が開きます)。": "Pending payments will be sent to this device. You can decide right from the notification's Approve / Reject buttons (on iPhone, tapping the notification opens this screen).",
    "テスト通知を送る": "Send a test notification",
    "この端末の通知をオフ": "Turn off on this device",
    "オンにすると、承認待ちが出たときにこの端末へ通知が届きます。": "Turn this on to get a notification on this device whenever a payment needs your approval.",
    "通知をオンにする": "Turn on notifications",
    "この端末では通知がブロックされています。端末の設定でこのアプリの通知を許可してから、もう一度開いてください。": "Notifications are blocked on this device. Allow notifications for this app in your device settings, then open it again.",
    "Safariの下にある共有ボタン(四角から矢印)を押す": "Tap the Share button (square with an arrow) at the bottom of Safari",
    "「ホーム画面に追加」を選ぶ": "Choose \"Add to Home Screen\"",
    "ホーム画面にできた「財布番」から開いて、ここで通知をオンにする": "Open Saifuban from your Home Screen and turn on notifications here",
    "iPhoneでは、ホーム画面に追加したアプリからだけ通知を受け取れます(iOS 16.4以降)。": "On iPhone, notifications only work from the app added to your Home Screen (iOS 16.4 or later).",
    "このブラウザは通知に対応していません。iPhoneはSafari、AndroidはChromeで開いてください。": "This browser doesn't support notifications. Use Safari on iPhone or Chrome on Android.",
    "合言葉(アカウント)": "Passphrase (your account)",
    "別の端末で開くときや、スマホを替えたときに使います。人に見せないでください。": "Use it to open Saifuban on another device or after changing phones. Keep it private.",
    "この端末から外す": "Sign out of this device",
    "APIキーを預けて、使いすぎを確実に止める(パソコンで使う人向け)": "Store your API keys to hard-stop overspending (for computer use)",
    "しくみ": "How it works",
    "本物のAPIキーは財布番が暗号化して保管し、AIにはエージェントキー(sbk_…)だけを渡します。AIの通信は財布番を通るので、今日の予算を使い切った時点で止まり、実際の利用料が履歴に記録されます。": "Saifuban stores your real API key encrypted and gives your AI only an agent key (sbk_…). Your AI's requests go through Saifuban, so they stop as soon as today's budget runs out, and the actual cost is recorded in History.",
    "AIにはAPIキーの代わりに、つなぐURLの最後にある sbk_… の部分(エージェントキー)を設定します。": "Give your AI the sbk_… part at the end of the connection URL (the agent key) instead of the API key.",
    "未設定": "Not set",
    "新しいキーに差し替える": "Replace with a new key",
    "本物のAPIキーを預ける": "Store your real API key",
    "保存": "Save",
    "預けるのをやめる": "Remove key",
    "AIに設定する住所(ベースURL):": "Base URL to set in your AI:",
    "住所をコピー": "Copy URL",
    "1つのキーでClaude・GPT・Gemini・Llamaなど何百種類ものモデルを使えるサービス。迷ったらこれ1つで足ります。実際にかかった金額がそのまま記録されます。": "One key for hundreds of models, including Claude, GPT, Gemini and Llama. If you're not sure, this one is enough. The actual cost is recorded as-is.",
    "Claude Code に使うときは ANTHROPIC_BASE_URL にこの住所、ANTHROPIC_API_KEY にエージェントキーを設定します。": "For Claude Code, set ANTHROPIC_BASE_URL to this URL and ANTHROPIC_API_KEY to your agent key.",
    "OpenAIのSDKやツールでは OPENAI_BASE_URL にこの住所、OPENAI_API_KEY にエージェントキーを設定します。": "For OpenAI SDKs and tools, set OPENAI_BASE_URL to this URL and OPENAI_API_KEY to your agent key.",
    "OpenAI互換の住所です。Google純正のSDKを使う場合は末尾の /v1beta/openai を外してください。": "This is an OpenAI-compatible URL. For Google's own SDK, remove /v1beta/openai from the end.",
    "1日いくらまで(円)": "Daily budget (¥)",
    "1日いくらまで($)": "Daily budget ($)",
    "聞かずに払っていい額($)": "Auto-approve up to ($)",
    "1回の上限($)": "Per-payment limit ($)",
    "通貨": "Currency",
    "円 (¥)": "Yen (¥)",
    "ドル ($)": "Dollars ($)",
    "ドル表示にしました": "Switched to dollars",
    "円表示にしました": "Switched to yen",
    "聞かずに払っていい額(円)": "Auto-approve up to (¥)",
    "つなぎ方を見る": "How to connect",
    "もっと細かく": "More options",
    "1回の上限(円)": "Per-payment limit (¥)",
    "使ってよい支払先(空欄ならどこでもOK)": "Allowed merchants (blank = any)",
    "例: OpenRouter, AWS": "e.g. OpenRouter, AWS",
    "このAIを止める": "Stop this AI",
    "再開する": "Resume",
    "つなぐURLを作り直す": "Make a new connection URL",
    "このAIを削除": "Delete this AI",
    "もう一度押すと削除します": "Tap again to delete",
    "判定の順番:緊急停止 → AIの停止 → 支払先 → 1回の上限 → 1日の予算 → 聞かずに払っていい額。予算は日本時間0時にリセット、24時間放置の申請は失効します。": "Checked in this order: emergency stop → AI stopped → merchant → per-payment limit → daily budget → auto-approve amount. Budgets reset at midnight Japan time (UTC+9), and requests left for 24 hours expire.",
    // toasts / messages
    "先にホーム画面に追加してください": "Add it to your Home Screen first",
    "通知が許可されませんでした": "Notifications weren't allowed",
    "通知をオンにしました。テスト通知を送りました": "Notifications are on. A test notification was sent",
    "通知をオンにしました": "Notifications are on",
    "通知をオンにできませんでした": "Couldn't turn on notifications",
    "この端末の通知をオフにしました": "Notifications turned off on this device",
    "コピーしました": "Copied",
    "選択しました。長押しでコピーしてください": "Selected. Long-press to copy",
    "合言葉の形が違います(sbo_ で始まる52文字)": "That doesn't look right (52 characters starting with sbo_)",
    "この端末で使えるようになりました": "Ready on this device",
    "合言葉を保存したら、もう一度押す": "Save your passphrase, then tap again",
    "承認しました。AIに支払いOKが伝わります": "Approved. Your AI will be told it can pay",
    "却下しました": "Rejected",
    "停止を解除しました": "All AIs resumed",
    "全AIを停止しました": "All AIs stopped",
    "削除しました": "Deleted",
    "つなぐURLができました": "Your connection URL is ready",
    "もう一度押すと今のURLは使えなくなります": "Tap again — the current URL will stop working",
    "新しい接続URLを発行しました": "New connection URL created",
    "テスト通知を送りました": "Test notification sent",
    "送れませんでした。通知をオンにし直してください": "Couldn't send. Please turn notifications on again",
    "APIキーを正しく貼り付けてください": "Please paste a valid API key",
    "もう一度押すとやめます": "Tap again to remove",
    "この申請はもう判断済みか、失効しています": "This request was already decided or has expired",
    "このAIは見つかりません": "This AI wasn't found",
    "合言葉が正しくありません": "Incorrect passphrase",
    "つながりませんでした。電波のよいところでもう一度試してください": "Couldn't connect. Please try again with a better connection",
    "AIは20個までつなげます": "You can connect up to 20 AIs",
    "サーバーでエラーが起きました。少し待ってもう一度試してください": "Server error. Please wait a moment and try again",
    // server notes
    "人間の承認が必要": "Needs your approval",
    "人間が承認": "Approved by you",
    "人間が却下": "Rejected by you",
    "人間が承認(通知から)": "Approved by you (notification)",
    "人間が却下(通知から)": "Rejected by you (notification)",
    "このAIは停止中": "This AI is stopped",
    "許可していない支払先": "Merchant not allowed",
    "実費": "actual cost",
    "料金表": "price list",
    "不明なモデル": "unknown model",
    "自動OKの上限を超えています": "Over the auto-approve limit",
  };
  const R = [
    [/^「(.+)」をAIにつなぐ$/, (m, n) => `Connect "${n}" to your AI`],
    [/^使った (\S+) \/ (\S+)$/, (m, a, b) => `Spent ${a} of ${b}`],
    [/^([¥$][\d,.]+)まで$/, (m, a) => `Up to ${a}`],
    [/^金額を円とドルのどちらで表示・設定するかを選べます。ドルは1ドル=([\d.]+)円で換算します\(中身の記録は円のままです\)。$/,
      (m, r) => `Choose whether amounts are shown and set in yen or dollars. Dollars are converted at $1 = ¥${r} (records are kept in yen).`],
    [/^預かり中 (.+)$/, (m, a) => `Stored ${a}`],
    [/^利用料はOpenRouterでは実費、それ以外はトークン数×料金表の目安\(1ドル=([\d.]+)円\)で計算します。予算を超えるのは最大で最後の1回分です。$/,
      (m, r) => `Costs are exact for OpenRouter; for others they're estimated from token counts and a price list ($1 = ¥${r}). At most the last request can go over budget.`],
    [/^このMCPサーバーにつないで、ツールを試して、「財布番」というスキルとして保存して。認証はなし。URL: (.*)$/,
      (m, u) => `Connect to this MCP server, try its tools, and save it as a skill called "Saifuban". No authentication. URL: ${u === "(ステップ1のURL)" ? "(the URL from step 1)" : u}`],
    [/^(.+)を再開しました$/, (m, n) => `${n} resumed`],
    [/^(.+)を止めました$/, (m, n) => `${n} stopped`],
    [/^(.+)のルールを保存しました$/, (m, n) => `Saved rules for ${n}`],
    [/^(.+)のキーを預かりました$/, (m, n) => `${n} key stored`],
    [/^(.+)のキーを外しました$/, (m, n) => `${n} key removed`],
    [/^うまくいきませんでした\((.*)\)$/, (m, c) => `Something went wrong (${c})`],
  ];
  // server notes that appear inside "agent · time · note" lines
  const A = (x) => (/円$/.test(x) ? "¥" + x.replace(/円$/, "") : x);
  const SUB = [
    [/自動承認\((.+?)以下\)/g, (m, n) => `Auto-approved (≤ ${A(n)})`],
    [/聞かずに払っていい額\((.+?)\)を超過/g, (m, n) => `Over auto-approve amount (${A(n)})`],
    [/1回の上限\((.+?)\)を超過/g, (m, n) => `Over per-payment limit (${A(n)})`],
    [/1日の予算\((.+?)\)を超過/g, (m, n) => `Over daily budget (${A(n)})`],
    [/API利用\(中継で自動計測・([^)]*)\)/g, (m, n) => `API usage (metered via relay · ${n})`],
    [/入力([\d,]+) \/ 出力([\d,]+) トークン/g, (m, a, b) => `${a} in / ${b} out tokens`],
    [/すべて\(予算と承認ルールの範囲内\)/g, () => "anything (within budget and rules)"],
    [/緊急停止中/g, () => "Emergency stop"],
    [/人間が承認\(通知から\)/g, () => "Approved by you (notification)"],
    [/人間が却下\(通知から\)/g, () => "Rejected by you (notification)"],
    [/人間の承認が必要/g, () => "Needs your approval"],
    [/人間が承認/g, () => "Approved by you"],
    [/人間が却下/g, () => "Rejected by you"],
    [/このAIは停止中/g, () => "This AI is stopped"],
    [/許可していない支払先/g, () => "Merchant not allowed"],
    [/\(理由なし\)/g, () => "(no reason given)"],
  ];
  const JA = /[ぁ-んァ-ヶ一-龠]/;
  function tr(s) {
    const t = s.trim();
    if (!t || !JA.test(t)) return null;
    let out = D[t];
    if (out === undefined) for (const [re, f] of R) { const m = t.match(re); if (m) { out = f(...m); break; } }
    if (out === undefined) {
      let x = t, hit = false;
      for (const [re, f] of SUB) { const y = x.replace(re, f); if (y !== x) { hit = true; x = y; } }
      if (hit) out = x;
    }
    if (out === undefined) return null;
    return s.replace(t, out);
  }
  // ブラウザの自動翻訳と書き換え合いになって固まらないよう、同じ場所は数回までしか書き換えない
  const hits = new WeakMap();
  function ok(n) { const c = (hits.get(n) || 0) + 1; hits.set(n, c); return c <= 3; }
  function walk(root) {
    if (root.nodeType === 3) { const v = tr(root.nodeValue); if (v !== null && ok(root)) root.nodeValue = v; return; }
    if (root.nodeType !== 1 || root.closest("script,style,input,textarea")) return;
    const w = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
    let n; const list = [];
    while ((n = w.nextNode())) if (!n.parentNode.closest("script,style")) list.push(n);
    for (const n of list) { const v = tr(n.nodeValue); if (v !== null && ok(n)) n.nodeValue = v; }
    const els = root.querySelectorAll ? [root, ...root.querySelectorAll("[placeholder],[aria-label],[title]")] : [];
    for (const e of els) for (const a of ["placeholder", "aria-label", "title"]) {
      const v = e.getAttribute && e.getAttribute(a); if (v) { const x = tr(v); if (x !== null && ok(e)) e.setAttribute(a, x); }
    }
  }
  function start() {
    // ブラウザの自動翻訳を止める(英語表示を選んだ人に日本語へ戻されないように)
    const h = document.documentElement;
    h.setAttribute("translate", "no"); h.classList.add("notranslate");
    if (!document.querySelector('meta[name="google"]')) { const m = document.createElement("meta"); m.name = "google"; m.content = "notranslate"; document.head.appendChild(m); }
    document.title = "Saifuban — your AI asks before it spends";
    walk(document.body);
    new MutationObserver((ms) => {
      for (const m of ms) {
        if (m.type === "characterData") walk(m.target);
        else if (m.type === "attributes") walk(m.target);
        else m.addedNodes.forEach(walk);
      }
    }).observe(document.body, { childList: true, subtree: true, characterData: true, attributes: true, attributeFilter: ["placeholder", "aria-label", "title"] });
  }
  if (document.body) start(); else document.addEventListener("DOMContentLoaded", start);
})();
