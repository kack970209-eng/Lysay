// 管理后台页面（单页，纯 HTML + JS）。注意：内部脚本不要用反引号和 ${}，避免与外层模板字符串冲突。
export const ADMIN_HTML = String.raw`<!doctype html>
<html lang="zh-Hant">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Lysay 管理后台</title>
<style>
  :root {
    --bg: #f5f5f7; --card: #ffffff; --text: #1d1d1f; --sub: #6e6e73; --line: #e5e5ea;
    --blue: #007aff; --red: #ff3b30; --green: #34c759; --orange: #ff9500;
  }
  @media (prefers-color-scheme: dark) {
    :root { --bg: #000; --card: #1c1c1e; --text: #f5f5f7; --sub: #98989d; --line: #2c2c2e; }
  }
  * { box-sizing: border-box; }
  body { margin: 0; font: 15px/1.5 -apple-system, BlinkMacSystemFont, "PingFang TC", "Microsoft JhengHei", sans-serif;
         background: var(--bg); color: var(--text); }
  header { position: sticky; top: 0; z-index: 2; display: flex; align-items: center; gap: 12px; padding: 14px 24px;
           background: color-mix(in srgb, var(--bg) 80%, transparent); backdrop-filter: blur(20px);
           border-bottom: 1px solid var(--line); }
  header h1 { font-size: 19px; margin: 0; flex: 1; }
  main { max-width: 1200px; margin: 0 auto; padding: 24px; }
  .stats { display: grid; grid-template-columns: repeat(auto-fit, minmax(180px, 1fr)); gap: 12px; margin-bottom: 20px; }
  .card { background: var(--card); border-radius: 16px; padding: 16px 18px; box-shadow: 0 1px 2px rgba(0,0,0,.05); }
  .stat .n { font-size: 30px; font-weight: 700; }
  .stat .l { color: var(--sub); font-size: 13px; }
  h2 { font-size: 17px; margin: 24px 0 10px; }
  input, select, button { font: inherit; }
  input[type=text], input[type=password], input[type=number] {
    padding: 9px 12px; border-radius: 10px; border: 1px solid var(--line); background: var(--card); color: var(--text); }
  button { padding: 7px 12px; border-radius: 9px; border: 0; background: var(--line); color: var(--text); cursor: pointer; }
  button.primary { background: var(--blue); color: #fff; }
  button.danger { background: color-mix(in srgb, var(--red) 15%, transparent); color: var(--red); }
  button:disabled { opacity: .5; }
  table { width: 100%; border-collapse: collapse; }
  th, td { text-align: left; padding: 10px 8px; border-bottom: 1px solid var(--line); vertical-align: top; }
  th { color: var(--sub); font-weight: 500; font-size: 13px; }
  .badge { display: inline-block; padding: 2px 8px; border-radius: 999px; font-size: 12px; font-weight: 600; }
  .pro { background: color-mix(in srgb, var(--blue) 15%, transparent); color: var(--blue); }
  .none { background: var(--line); color: var(--sub); }
  .off { background: color-mix(in srgb, var(--red) 15%, transparent); color: var(--red); }
  .actions { display: flex; flex-wrap: wrap; gap: 6px; }
  .muted { color: var(--sub); font-size: 13px; }
  #login { max-width: 360px; margin: 15vh auto; text-align: center; }
  #login input { width: 100%; margin: 14px 0; }
  .toolbar { display: flex; gap: 8px; margin-bottom: 10px; }
  .toolbar input { flex: 1; }
  .plans td input { width: 110px; }
  #toast { position: fixed; bottom: 24px; left: 50%; transform: translateX(-50%); background: var(--text); color: var(--bg);
           padding: 10px 18px; border-radius: 12px; opacity: 0; transition: opacity .2s; pointer-events: none; }
</style>
</head>
<body>
<div id="login" class="card" hidden>
  <h1>Lysay 管理后台</h1>
  <input id="pw" type="password" placeholder="管理员密码" autocomplete="current-password">
  <button class="primary" id="loginBtn" style="width:100%">登录</button>
  <p class="muted" id="loginErr"></p>
</div>

<div id="app" hidden>
  <header>
    <h1>Lysay 管理后台</h1>
    <button id="refresh">重新整理</button>
    <button id="logout">登出</button>
  </header>
  <main>
    <div class="stats">
      <div class="card stat"><div class="n" id="sUsers">-</div><div class="l">注册用户</div></div>
      <div class="card stat"><div class="n" id="sPro">-</div><div class="l">Pro 订阅中</div></div>
      <div class="card stat"><div class="n" id="sNew">-</div><div class="l">24 小时内新用户</div></div>
      <div class="card stat"><div class="n" id="sFree">-</div><div class="l">免费 AI 语音额度</div></div>
    </div>

    <h2>用户</h2>
    <div class="card">
      <div class="toolbar">
        <input id="q" type="text" placeholder="搜索 Email、名字或 ID">
        <button id="search">搜索</button>
      </div>
      <table>
        <thead><tr><th>用户</th><th>登录方式</th><th>注册 / 最后登录</th><th>AI 语音已用</th><th>订阅套餐</th><th>状态</th><th>操作</th></tr></thead>
        <tbody id="users"></tbody>
      </table>
    </div>

    <h2>套餐与价格</h2>
    <div class="card">
      <table class="plans">
        <thead><tr><th>ID</th><th>名称</th><th>价格</th><th>币别</th><th>天数</th><th></th></tr></thead>
        <tbody id="plans"></tbody>
      </table>
    </div>
  </main>
</div>
<div id="toast"></div>

<script>
var token = localStorage.getItem("lysayAdmin") || "";
var plans = [];

function $(id) { return document.getElementById(id); }
function esc(s) { return String(s == null ? "" : s).replace(/[&<>"']/g, function (c) {
  return { "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[c]; }); }
function fmtDate(ms) { if (!ms) return "-"; var d = new Date(ms);
  return d.getFullYear() + "-" + ("0" + (d.getMonth() + 1)).slice(-2) + "-" + ("0" + d.getDate()).slice(-2) + " " +
         ("0" + d.getHours()).slice(-2) + ":" + ("0" + d.getMinutes()).slice(-2); }
function fmtDur(sec) { sec = sec || 0; var h = Math.floor(sec / 3600), m = Math.floor((sec % 3600) / 60);
  return h + " 小时 " + m + " 分"; }
function toast(msg) { var t = $("toast"); t.textContent = msg; t.style.opacity = 1;
  setTimeout(function () { t.style.opacity = 0; }, 1800); }

function api(path, opts) {
  opts = opts || {};
  opts.headers = Object.assign({ "content-type": "application/json" }, opts.headers || {});
  if (token) opts.headers.authorization = "Bearer " + token;
  return fetch(path, opts).then(function (r) {
    return r.json().then(function (data) {
      if (r.status === 401 && path !== "/admin/api/login") { showLogin(); throw new Error(data.error || "请重新登录"); }
      if (!r.ok) throw new Error(data.error || ("错误 " + r.status));
      return data;
    });
  });
}

function showLogin() { $("app").hidden = true; $("login").hidden = false; }
function showApp() { $("login").hidden = true; $("app").hidden = false; loadAll(); }

$("loginBtn").onclick = function () {
  api("/admin/api/login", { method: "POST", body: JSON.stringify({ password: $("pw").value }) })
    .then(function (d) { token = d.token; localStorage.setItem("lysayAdmin", token); showApp(); })
    .catch(function (e) { $("loginErr").textContent = e.message; });
};
$("pw").addEventListener("keydown", function (e) { if (e.key === "Enter") $("loginBtn").click(); });
$("logout").onclick = function () { token = ""; localStorage.removeItem("lysayAdmin"); showLogin(); };
$("refresh").onclick = function () { loadAll(); };
$("search").onclick = function () { loadUsers(); };
$("q").addEventListener("keydown", function (e) { if (e.key === "Enter") loadUsers(); });

function loadAll() { loadStats(); loadPlans().then(loadUsers); }

function loadStats() {
  api("/admin/api/stats").then(function (s) {
    $("sUsers").textContent = s.users; $("sPro").textContent = s.pro; $("sNew").textContent = s.newToday;
    $("sFree").textContent = Math.round(s.freeSeconds / 3600) + " 小时";
  }).catch(function (e) { toast(e.message); });
}

function loadPlans() {
  return api("/admin/api/plans").then(function (d) {
    plans = d.plans;
    $("plans").innerHTML = plans.map(function (p) {
      return "<tr data-id='" + esc(p.id) + "'><td>" + esc(p.id) + "</td>" +
        "<td><input type='text' class='pn' value='" + esc(p.name) + "'></td>" +
        "<td><input type='number' class='pp' value='" + esc(p.price) + "'></td>" +
        "<td><input type='text' class='pc' value='" + esc(p.currency) + "'></td>" +
        "<td><input type='number' class='pd' value='" + esc(p.days) + "'></td>" +
        "<td><button class='primary' onclick='savePlan(this)'>保存</button></td></tr>";
    }).join("");
  }).catch(function (e) { toast(e.message); });
}

function savePlan(btn) {
  var tr = btn.closest("tr");
  api("/admin/api/plans/" + tr.dataset.id, { method: "PUT", body: JSON.stringify({
    name: tr.querySelector(".pn").value, price: tr.querySelector(".pp").value,
    currency: tr.querySelector(".pc").value, days: tr.querySelector(".pd").value }) })
    .then(function () { toast("已保存"); loadPlans(); }).catch(function (e) { toast(e.message); });
}

function loadUsers() {
  var q = encodeURIComponent($("q").value.trim());
  api("/admin/api/users?q=" + q).then(function (d) {
    if (!d.users.length) { $("users").innerHTML = "<tr><td colspan='7' class='muted'>没有用户</td></tr>"; return; }
    $("users").innerHTML = d.users.map(function (u) {
      var plan = u.plan
        ? "<span class='badge pro'>" + esc(u.plan.name) + "</span><div class='muted'>到期 " + fmtDate(u.plan.expiresAt) + "</div>"
        : "<span class='badge none'>无</span>";
      var status = u.status === "active" ? "<span class='badge pro'>正常</span>" : "<span class='badge off'>已停用</span>";
      var planBtns = plans.map(function (p) {
        return "<button onclick=\"setPlan('" + u.id + "','" + p.id + "')\">升级" + esc(p.name) + "</button>";
      }).join("");
      return "<tr><td><b>" + esc(u.name || "（未提供名字）") + "</b><div class='muted'>" + esc(u.email || "") +
        "</div><div class='muted'>" + esc(u.id) + "</div></td>" +
        "<td>" + (u.provider === "apple" ? "Apple" : "Google") + "</td>" +
        "<td>" + fmtDate(u.createdAt) + "<div class='muted'>" + fmtDate(u.lastLoginAt) + "</div></td>" +
        "<td>" + fmtDur(u.aiSecondsUsed) + "</td>" +
        "<td>" + plan + "</td><td>" + status + "</td>" +
        "<td><div class='actions'>" + planBtns +
        (u.plan ? "<button class='danger' onclick=\"setPlan('" + u.id + "','none')\">取消套餐</button>" : "") +
        "<button onclick=\"resetUsage('" + u.id + "')\">重置额度</button>" +
        (u.status === "active"
          ? "<button class='danger' onclick=\"setStatus('" + u.id + "','disabled')\">停用</button>"
          : "<button onclick=\"setStatus('" + u.id + "','active')\">启用</button>") +
        "<button class='danger' onclick=\"delUser('" + u.id + "')\">删除</button>" +
        "</div></td></tr>";
    }).join("");
  }).catch(function (e) { toast(e.message); });
}

function setPlan(id, plan) {
  var label = plan === "none" ? "取消这个用户的套餐？" : "为这个用户开通 / 续期这个套餐？";
  if (!confirm(label)) return;
  api("/admin/api/users/" + id + "/plan", { method: "POST", body: JSON.stringify({ plan: plan }) })
    .then(function () { toast("已更新"); loadAll(); }).catch(function (e) { toast(e.message); });
}
function setStatus(id, status) {
  api("/admin/api/users/" + id + "/status", { method: "POST", body: JSON.stringify({ status: status }) })
    .then(function () { toast("已更新"); loadUsers(); }).catch(function (e) { toast(e.message); });
}
function resetUsage(id) {
  if (!confirm("把这个用户的 AI 语音已用时间归零？")) return;
  api("/admin/api/users/" + id + "/reset-usage", { method: "POST" })
    .then(function () { toast("已重置"); loadUsers(); }).catch(function (e) { toast(e.message); });
}
function delUser(id) {
  if (!confirm("删除这个用户和他的所有同步数据？此操作无法复原。")) return;
  api("/admin/api/users/" + id, { method: "DELETE" })
    .then(function () { toast("已删除"); loadAll(); }).catch(function (e) { toast(e.message); });
}

if (token) showApp(); else showLogin();
</script>
</body>
</html>`;
