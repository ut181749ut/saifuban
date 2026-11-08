// AIの財布番 — 通知を受け取り、通知のボタンから承認・却下する
self.addEventListener("install", () => self.skipWaiting());
self.addEventListener("activate", (e) => e.waitUntil(self.clients.claim()));

self.addEventListener("push", (e) => {
  let d = {};
  try { d = e.data ? e.data.json() : {}; } catch (_) { d = { title: "AIの財布番", body: e.data ? e.data.text() : "" }; }
  const opt = {
    body: d.body || "",
    icon: "icon-192.png",
    badge: "icon-192.png",
    tag: d.id ? "req-" + d.id : "saifuban",
    renotify: true,
    requireInteraction: d.type === "pending",
    data: d,
  };
  const en = d.lang === "en";
  if (d.type === "pending" && d.approve_url) {
    opt.actions = en
      ? [{ action: "approve", title: "Approve" }, { action: "reject", title: "Reject" }]
      : [{ action: "approve", title: "承認する" }, { action: "reject", title: "却下" }];
  }
  e.waitUntil(Promise.all([
    self.registration.showNotification(d.title || (en ? "Saifuban" : "AIの財布番"), opt),
    self.clients.matchAll({ type: "window" }).then((ws) => ws.forEach((w) => w.postMessage({ type: "refresh" }))),
  ]));
});

self.addEventListener("notificationclick", (e) => {
  const d = e.notification.data || {};
  e.notification.close();
  if (e.action === "approve" || e.action === "reject") {
    const approve = e.action === "approve";
    e.waitUntil(
      fetch(approve ? d.approve_url : d.reject_url, { method: "POST" })
        .then((r) => r.json())
        .then((j) => {
          const en = d.lang === "en";
          const title = j.ok ? (approve ? (en ? "Approved" : "承認しました") : (en ? "Rejected" : "却下しました"))
            : (en ? "This request was already decided" : "この申請はもう判断済みです");
          const body = j.ok ? String(d.short || String(d.title || "").replace(/^承認待ち /, "")) : "";
          return self.registration.showNotification(title, { body, tag: "done-" + d.id, icon: "icon-192.png" });
        })
        .catch(() => self.registration.showNotification(d.lang === "en" ? "Couldn't send" : "送れませんでした",
          { body: d.lang === "en" ? "Open the app to decide" : "アプリを開いて判断してください", icon: "icon-192.png" }))
        .then(() => self.clients.matchAll({ type: "window" }).then((ws) => ws.forEach((w) => w.postMessage({ type: "refresh" }))))
    );
    return;
  }
  e.waitUntil(
    self.clients.matchAll({ type: "window", includeUncontrolled: true }).then((ws) => {
      for (const w of ws) { if ("focus" in w) { w.postMessage({ type: "refresh" }); return w.focus(); } }
      return self.clients.openWindow("./");
    })
  );
});
