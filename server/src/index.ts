// Lysay 后端：登录（Apple / Google）、AI 语音用量与订阅、剪贴板同步、管理后台
import { ADMIN_HTML } from "./admin";
import { HOME_HTML, PRIVACY_HTML, TERMS_HTML } from "./pages";

interface Env {
  DB: any; // D1Database
  SESSION_SECRET: string;
  ADMIN_PASSWORD: string;
  GOOGLE_CLIENT_IDS: string; // 逗号分隔
  APPLE_AUDIENCES: string;   // 逗号分隔（App 的 Bundle ID）
  FREE_AI_SECONDS: string;   // 免费 AI 语音额度（秒）
}

const DAY = 24 * 3600 * 1000;

// ───────────────────────── 通用工具 ─────────────────────────

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: {
      "content-type": "application/json; charset=utf-8",
      "access-control-allow-origin": "*",
      "access-control-allow-headers": "authorization, content-type",
      "access-control-allow-methods": "GET, POST, PUT, DELETE, OPTIONS",
    },
  });
}

function fail(message: string, status = 400): Response {
  return json({ error: message }, status);
}

function b64urlEncode(bytes: Uint8Array): string {
  let s = "";
  for (const b of bytes) s += String.fromCharCode(b);
  return btoa(s).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function b64urlDecode(str: string): Uint8Array {
  const s = str.replace(/-/g, "+").replace(/_/g, "/") + "===".slice((str.length + 3) % 4);
  const bin = atob(s);
  const out = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) out[i] = bin.charCodeAt(i);
  return out;
}

const enc = new TextEncoder();
const dec = new TextDecoder();

function list(v: string | undefined): string[] {
  return (v || "").split(",").map((s) => s.trim()).filter(Boolean);
}

async function readJson(req: Request): Promise<any> {
  try {
    return await req.json();
  } catch {
    return {};
  }
}

// ───────────────────────── 会话令牌（HMAC JWT） ─────────────────────────

async function hmacKey(secret: string): Promise<CryptoKey> {
  return crypto.subtle.importKey("raw", enc.encode(secret), { name: "HMAC", hash: "SHA-256" }, false, [
    "sign",
    "verify",
  ]);
}

async function signToken(env: Env, payload: Record<string, unknown>, ttlMs: number): Promise<string> {
  const header = b64urlEncode(enc.encode(JSON.stringify({ alg: "HS256", typ: "JWT" })));
  const body = b64urlEncode(enc.encode(JSON.stringify({ ...payload, exp: Date.now() + ttlMs })));
  const sig = await crypto.subtle.sign("HMAC", await hmacKey(env.SESSION_SECRET), enc.encode(`${header}.${body}`));
  return `${header}.${body}.${b64urlEncode(new Uint8Array(sig))}`;
}

async function verifyToken(env: Env, token: string): Promise<any | null> {
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const ok = await crypto.subtle.verify(
    "HMAC",
    await hmacKey(env.SESSION_SECRET),
    b64urlDecode(parts[2]),
    enc.encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) return null;
  const payload = JSON.parse(dec.decode(b64urlDecode(parts[1])));
  if (typeof payload.exp !== "number" || payload.exp < Date.now()) return null;
  return payload;
}

function bearer(req: Request): string | null {
  const h = req.headers.get("authorization") || "";
  return h.startsWith("Bearer ") ? h.slice(7) : null;
}

// ───────────────────────── 第三方登录验证 ─────────────────────────

const jwksCache = new Map<string, { at: number; keys: any[] }>();

async function getJwks(url: string): Promise<any[]> {
  const hit = jwksCache.get(url);
  if (hit && Date.now() - hit.at < 3600 * 1000) return hit.keys;
  const res = await fetch(url);
  if (!res.ok) throw new Error("无法获取公钥");
  const data: any = await res.json();
  jwksCache.set(url, { at: Date.now(), keys: data.keys || [] });
  return data.keys || [];
}

async function verifyIdToken(token: string, jwksUrl: string, issuers: string[], audiences: string[]): Promise<any> {
  const parts = token.split(".");
  if (parts.length !== 3) throw new Error("令牌格式错误");
  const header = JSON.parse(dec.decode(b64urlDecode(parts[0])));
  const payload = JSON.parse(dec.decode(b64urlDecode(parts[1])));
  const keys = await getJwks(jwksUrl);
  const jwk = keys.find((k) => k.kid === header.kid);
  if (!jwk) throw new Error("找不到对应公钥");
  const key = await crypto.subtle.importKey("jwk", jwk, { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" }, false, [
    "verify",
  ]);
  const ok = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    b64urlDecode(parts[2]),
    enc.encode(`${parts[0]}.${parts[1]}`),
  );
  if (!ok) throw new Error("签名无效");
  if (!issuers.includes(payload.iss)) throw new Error("签发者不符");
  const aud = Array.isArray(payload.aud) ? payload.aud : [payload.aud];
  if (!aud.some((a: string) => audiences.includes(a))) throw new Error(`audience 不符：${aud.join(",")}`);
  if (typeof payload.exp !== "number" || payload.exp * 1000 < Date.now()) throw new Error("令牌已过期");
  return payload;
}

// ───────────────────────── 用户与订阅 ─────────────────────────

async function upsertUser(env: Env, provider: string, sub: string, email: string | null, name: string | null) {
  const now = Date.now();
  const existing: any = await env.DB.prepare("SELECT * FROM users WHERE provider = ? AND provider_sub = ?")
    .bind(provider, sub)
    .first();
  if (existing) {
    await env.DB.prepare(
      "UPDATE users SET last_login_at = ?, email = COALESCE(?, email), name = COALESCE(?, name) WHERE id = ?",
    )
      .bind(now, email, name, existing.id)
      .run();
    return { ...existing, email: email ?? existing.email, name: name ?? existing.name, last_login_at: now };
  }
  const id = crypto.randomUUID();
  await env.DB.prepare(
    "INSERT INTO users (id, provider, provider_sub, email, name, created_at, last_login_at) VALUES (?, ?, ?, ?, ?, ?, ?)",
  )
    .bind(id, provider, sub, email, name, now, now)
    .run();
  return { id, provider, provider_sub: sub, email, name, status: "active", ai_seconds_used: 0, created_at: now, last_login_at: now };
}

async function profile(env: Env, user: any) {
  const sub: any = await env.DB.prepare(
    "SELECT s.*, p.name AS plan_name FROM subscriptions s LEFT JOIN plans p ON p.id = s.plan_id WHERE s.user_id = ?",
  )
    .bind(user.id)
    .first();
  const now = Date.now();
  const active = sub && sub.expires_at > now;
  const free = parseInt(env.FREE_AI_SECONDS || "14400", 10);
  const used = user.ai_seconds_used || 0;
  return {
    user: { id: user.id, email: user.email, name: user.name, provider: user.provider },
    plan: active ? { id: sub.plan_id, name: sub.plan_name || sub.plan_id, expiresAt: sub.expires_at } : null,
    ai: {
      pro: !!active,
      freeSeconds: free,
      usedSeconds: used,
      remainingSeconds: active ? -1 : Math.max(0, free - used),
    },
  };
}

async function currentUser(req: Request, env: Env): Promise<any | null> {
  const token = bearer(req);
  if (!token) return null;
  const payload = await verifyToken(env, token);
  if (!payload || payload.role !== "user") return null;
  const user: any = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(payload.sub).first();
  if (!user || user.status !== "active") return null;
  return user;
}

async function login(env: Env, provider: string, sub: string, email: string | null, name: string | null) {
  const user = await upsertUser(env, provider, sub, email, name);
  if (user.status !== "active") return fail("此账号已被停用，请联系客服", 403);
  const token = await signToken(env, { sub: user.id, role: "user" }, 180 * DAY);
  return json({ token, ...(await profile(env, user)) });
}

// ───────────────────────── 剪贴板同步 ─────────────────────────

async function sync(env: Env, user: any, body: any) {
  const since = typeof body.since === "number" ? body.since : 0;
  const stmts: any[] = [];
  const clampText = (t: unknown) => String(t ?? "").slice(0, 20000);

  for (const f of (body.folders || []).slice(0, 500)) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO clip_folders (id, user_id, name, sort, updated_at, deleted) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET name = excluded.name, sort = excluded.sort,
           updated_at = excluded.updated_at, deleted = excluded.deleted
         WHERE clip_folders.user_id = excluded.user_id AND excluded.updated_at > clip_folders.updated_at`,
      ).bind(f.id, user.id, String(f.name ?? "").slice(0, 200), Number(f.sort) || 0, Number(f.updatedAt) || 0, f.deleted ? 1 : 0),
    );
  }
  for (const it of (body.items || []).slice(0, 2000)) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO clip_items (id, user_id, folder_id, text, sort, updated_at, deleted) VALUES (?, ?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET folder_id = excluded.folder_id, text = excluded.text, sort = excluded.sort,
           updated_at = excluded.updated_at, deleted = excluded.deleted
         WHERE clip_items.user_id = excluded.user_id AND excluded.updated_at > clip_items.updated_at`,
      ).bind(it.id, user.id, it.folderId ?? null, clampText(it.text), Number(it.sort) || 0, Number(it.updatedAt) || 0, it.deleted ? 1 : 0),
    );
  }
  for (const h of (body.history || []).slice(0, 500)) {
    stmts.push(
      env.DB.prepare(
        `INSERT INTO clip_history (id, user_id, text, created_at, updated_at, deleted) VALUES (?, ?, ?, ?, ?, ?)
         ON CONFLICT(id) DO UPDATE SET text = excluded.text, updated_at = excluded.updated_at, deleted = excluded.deleted
         WHERE clip_history.user_id = excluded.user_id AND excluded.updated_at > clip_history.updated_at`,
      ).bind(h.id, user.id, clampText(h.text), Number(h.createdAt) || 0, Number(h.updatedAt) || 0, h.deleted ? 1 : 0),
    );
  }
  for (let i = 0; i < stmts.length; i += 50) {
    await env.DB.batch(stmts.slice(i, i + 50));
  }

  const serverTime = Date.now();
  const folders = await env.DB.prepare("SELECT * FROM clip_folders WHERE user_id = ? AND updated_at > ?")
    .bind(user.id, since).all();
  const items = await env.DB.prepare("SELECT * FROM clip_items WHERE user_id = ? AND updated_at > ?")
    .bind(user.id, since).all();
  const history = await env.DB.prepare(
    "SELECT * FROM clip_history WHERE user_id = ? AND updated_at > ? ORDER BY created_at DESC LIMIT 300",
  ).bind(user.id, since).all();

  return json({
    serverTime,
    folders: folders.results.map((f: any) => ({
      id: f.id, name: f.name, sort: f.sort, updatedAt: f.updated_at, deleted: !!f.deleted,
    })),
    items: items.results.map((i: any) => ({
      id: i.id, folderId: i.folder_id, text: i.text, sort: i.sort, updatedAt: i.updated_at, deleted: !!i.deleted,
    })),
    history: history.results.map((h: any) => ({
      id: h.id, text: h.text, createdAt: h.created_at, updatedAt: h.updated_at, deleted: !!h.deleted,
    })),
  });
}

// ───────────────────────── 管理后台 API ─────────────────────────

async function requireAdmin(req: Request, env: Env): Promise<boolean> {
  const token = bearer(req);
  if (!token) return false;
  const p = await verifyToken(env, token);
  return !!p && p.role === "admin";
}

function safeEqual(a: string, b: string): boolean {
  if (a.length !== b.length) return false;
  let r = 0;
  for (let i = 0; i < a.length; i++) r |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return r === 0;
}

async function adminApi(req: Request, env: Env, path: string): Promise<Response> {
  const method = req.method;

  if (path === "/admin/api/login" && method === "POST") {
    const body = await readJson(req);
    if (!env.ADMIN_PASSWORD || !safeEqual(String(body.password || ""), env.ADMIN_PASSWORD)) {
      return fail("密码错误", 401);
    }
    return json({ token: await signToken(env, { sub: "admin", role: "admin" }, 7 * DAY) });
  }

  if (!(await requireAdmin(req, env))) return fail("请先登录后台", 401);
  const now = Date.now();

  if (path === "/admin/api/stats" && method === "GET") {
    const users: any = await env.DB.prepare("SELECT COUNT(*) AS n FROM users").first();
    const pro: any = await env.DB.prepare("SELECT COUNT(*) AS n FROM subscriptions WHERE expires_at > ?").bind(now).first();
    const today: any = await env.DB.prepare("SELECT COUNT(*) AS n FROM users WHERE created_at > ?").bind(now - DAY).first();
    return json({ users: users.n, pro: pro.n, newToday: today.n, freeSeconds: parseInt(env.FREE_AI_SECONDS || "14400", 10) });
  }

  if (path === "/admin/api/users" && method === "GET") {
    const q = new URL(req.url).searchParams.get("q") || "";
    const like = `%${q}%`;
    const rows = await env.DB.prepare(
      `SELECT u.*, s.plan_id, s.expires_at, p.name AS plan_name
       FROM users u
       LEFT JOIN subscriptions s ON s.user_id = u.id
       LEFT JOIN plans p ON p.id = s.plan_id
       WHERE (? = '' OR u.email LIKE ? OR u.name LIKE ? OR u.id LIKE ?)
       ORDER BY u.created_at DESC LIMIT 500`,
    ).bind(q, like, like, like).all();
    return json({
      users: rows.results.map((u: any) => ({
        id: u.id,
        provider: u.provider,
        email: u.email,
        name: u.name,
        status: u.status,
        aiSecondsUsed: u.ai_seconds_used,
        createdAt: u.created_at,
        lastLoginAt: u.last_login_at,
        plan: u.plan_id && u.expires_at > now ? { id: u.plan_id, name: u.plan_name || u.plan_id, expiresAt: u.expires_at } : null,
      })),
    });
  }

  const m = path.match(/^\/admin\/api\/users\/([^/]+)(?:\/([a-z-]+))?$/);
  if (m) {
    const userId = decodeURIComponent(m[1]);
    const action = m[2];
    const user: any = await env.DB.prepare("SELECT * FROM users WHERE id = ?").bind(userId).first();
    if (!user) return fail("找不到用户", 404);

    if (!action && method === "DELETE") {
      await env.DB.batch([
        env.DB.prepare("DELETE FROM clip_folders WHERE user_id = ?").bind(userId),
        env.DB.prepare("DELETE FROM clip_items WHERE user_id = ?").bind(userId),
        env.DB.prepare("DELETE FROM clip_history WHERE user_id = ?").bind(userId),
        env.DB.prepare("DELETE FROM subscriptions WHERE user_id = ?").bind(userId),
        env.DB.prepare("DELETE FROM users WHERE id = ?").bind(userId),
      ]);
      return json({ ok: true });
    }

    if (action === "plan" && method === "POST") {
      const body = await readJson(req);
      const planId = String(body.plan || "");
      if (planId === "none") {
        await env.DB.prepare("DELETE FROM subscriptions WHERE user_id = ?").bind(userId).run();
        await env.DB.prepare(
          "INSERT INTO subscription_events (id, user_id, action, operator, created_at) VALUES (?, ?, 'revoke', 'admin', ?)",
        ).bind(crypto.randomUUID(), userId, now).run();
        return json({ ok: true });
      }
      const plan: any = await env.DB.prepare("SELECT * FROM plans WHERE id = ?").bind(planId).first();
      if (!plan) return fail("找不到套餐");
      const cur: any = await env.DB.prepare("SELECT * FROM subscriptions WHERE user_id = ?").bind(userId).first();
      // 还没到期就从到期日往后延，否则从现在开始
      const base = cur && cur.expires_at > now ? cur.expires_at : now;
      const expires = base + plan.days * DAY;
      await env.DB.prepare(
        `INSERT INTO subscriptions (user_id, plan_id, started_at, expires_at, updated_at) VALUES (?, ?, ?, ?, ?)
         ON CONFLICT(user_id) DO UPDATE SET plan_id = excluded.plan_id, expires_at = excluded.expires_at, updated_at = excluded.updated_at`,
      ).bind(userId, planId, now, expires, now).run();
      await env.DB.prepare(
        `INSERT INTO subscription_events (id, user_id, action, plan_id, amount, currency, expires_at, operator, created_at)
         VALUES (?, ?, 'grant', ?, ?, ?, ?, 'admin', ?)`,
      ).bind(crypto.randomUUID(), userId, planId, plan.price, plan.currency, expires, now).run();
      return json({ ok: true, expiresAt: expires });
    }

    if (action === "status" && method === "POST") {
      const body = await readJson(req);
      const status = body.status === "disabled" ? "disabled" : "active";
      await env.DB.prepare("UPDATE users SET status = ? WHERE id = ?").bind(status, userId).run();
      return json({ ok: true });
    }

    if (action === "reset-usage" && method === "POST") {
      await env.DB.prepare("UPDATE users SET ai_seconds_used = 0 WHERE id = ?").bind(userId).run();
      return json({ ok: true });
    }

    if (action === "events" && method === "GET") {
      const rows = await env.DB.prepare(
        "SELECT * FROM subscription_events WHERE user_id = ? ORDER BY created_at DESC LIMIT 50",
      ).bind(userId).all();
      return json({ events: rows.results });
    }
  }

  if (path === "/admin/api/plans" && method === "GET") {
    const rows = await env.DB.prepare("SELECT * FROM plans ORDER BY sort").all();
    return json({ plans: rows.results });
  }

  const pm = path.match(/^\/admin\/api\/plans\/([a-z0-9_-]+)$/);
  if (pm && method === "PUT") {
    const body = await readJson(req);
    await env.DB.prepare(
      "UPDATE plans SET name = COALESCE(?, name), price = COALESCE(?, price), currency = COALESCE(?, currency), days = COALESCE(?, days) WHERE id = ?",
    ).bind(
      body.name ?? null,
      body.price != null ? Math.round(Number(body.price)) : null,
      body.currency ?? null,
      body.days != null ? Math.round(Number(body.days)) : null,
      pm[1],
    ).run();
    return json({ ok: true });
  }

  return fail("找不到接口", 404);
}

// ───────────────────────── 入口 ─────────────────────────

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    const url = new URL(req.url);
    const path = url.pathname.replace(/\/+$/, "") || "/";

    if (req.method === "OPTIONS") return json({});

    try {
      if (path === "/health") return json({ ok: true, service: "lysay" });
      const html = (h: string) => new Response(h, { headers: { "content-type": "text/html; charset=utf-8" } });
      if (path === "/") return html(HOME_HTML);
      if (path === "/privacy") return html(PRIVACY_HTML);
      if (path === "/terms") return html(TERMS_HTML);

      if (path === "/admin") {
        return new Response(ADMIN_HTML, { headers: { "content-type": "text/html; charset=utf-8" } });
      }
      if (path.startsWith("/admin/api/")) return adminApi(req, env, path);

      // 登录
      if (path === "/v1/auth/apple" && req.method === "POST") {
        const body = await readJson(req);
        const p = await verifyIdToken(
          String(body.identityToken || ""),
          "https://appleid.apple.com/auth/keys",
          ["https://appleid.apple.com"],
          list(env.APPLE_AUDIENCES),
        );
        // Apple 只在第一次登录时给名字
        const name = body.fullName ? String(body.fullName).slice(0, 100) : null;
        return login(env, "apple", p.sub, p.email ?? null, name);
      }
      if (path === "/v1/auth/google" && req.method === "POST") {
        const body = await readJson(req);
        const p = await verifyIdToken(
          String(body.idToken || ""),
          "https://www.googleapis.com/oauth2/v3/certs",
          ["https://accounts.google.com", "accounts.google.com"],
          list(env.GOOGLE_CLIENT_IDS),
        );
        return login(env, "google", p.sub, p.email ?? null, p.name ?? null);
      }

      if (path === "/v1/plans" && req.method === "GET") {
        const rows = await env.DB.prepare("SELECT id, name, price, currency, days FROM plans WHERE active = 1 ORDER BY sort").all();
        return json({ plans: rows.results, freeSeconds: parseInt(env.FREE_AI_SECONDS || "14400", 10) });
      }

      // 以下需要登录
      if (path.startsWith("/v1/")) {
        const user = await currentUser(req, env);
        if (!user) return fail("请重新登录", 401);

        if (path === "/v1/me" && req.method === "GET") return json(await profile(env, user));

        if (path === "/v1/usage" && req.method === "POST") {
          const body = await readJson(req);
          const seconds = Math.max(0, Math.min(3600, Math.round(Number(body.seconds) || 0)));
          if (seconds > 0) {
            await env.DB.prepare("UPDATE users SET ai_seconds_used = ai_seconds_used + ? WHERE id = ?")
              .bind(seconds, user.id).run();
            user.ai_seconds_used = (user.ai_seconds_used || 0) + seconds;
          }
          return json(await profile(env, user));
        }

        if (path === "/v1/sync" && req.method === "POST") return sync(env, user, await readJson(req));

        if (path === "/v1/account" && req.method === "DELETE") {
          await env.DB.batch([
            env.DB.prepare("DELETE FROM clip_folders WHERE user_id = ?").bind(user.id),
            env.DB.prepare("DELETE FROM clip_items WHERE user_id = ?").bind(user.id),
            env.DB.prepare("DELETE FROM clip_history WHERE user_id = ?").bind(user.id),
            env.DB.prepare("DELETE FROM subscriptions WHERE user_id = ?").bind(user.id),
            env.DB.prepare("DELETE FROM users WHERE id = ?").bind(user.id),
          ]);
          return json({ ok: true });
        }
      }

      return fail("找不到接口", 404);
    } catch (e: any) {
      return fail(e?.message || "服务器错误", 500);
    }
  },
};
