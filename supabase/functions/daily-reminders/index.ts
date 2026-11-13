// @ts-nocheck
// Gửi thông báo đẩy: mỗi sáng 7h (giờ Việt Nam) nhắc ngày giỗ (âm lịch) và sinh nhật (dương lịch) của NGÀY MAI.
import { createClient } from "npm:@supabase/supabase-js@2";
import webpush from "npm:web-push@3.6.7";

const SITE = "https://letrinh258.github.io/gia---pha---le---cong/";
const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "content-type, apikey, authorization, x-cron-secret",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const json = (o, s = 200) => new Response(JSON.stringify(o), { status: s, headers: { ...CORS, "Content-Type": "application/json" } });

/* ===== Âm lịch (thuật toán Hồ Ngọc Đức, múi giờ +7), giống hệt trong app ===== */
const PI = Math.PI, INT = Math.floor, TZ = 7;
function jdFromDate(dd, mm, yy) { let a = INT((14 - mm) / 12), y = yy + 4800 - a, m = mm + 12 * a - 3; let jd = dd + INT((153 * m + 2) / 5) + 365 * y + INT(y / 4) - INT(y / 100) + INT(y / 400) - 32045; if (jd < 2299161) jd = dd + INT((153 * m + 2) / 5) + 365 * y + INT(y / 4) - 32083; return jd }
function jdToDate(jd) { let a, b, c; if (jd > 2299160) { a = jd + 32044; b = INT((4 * a + 3) / 146097); c = a - INT((b * 146097) / 4) } else { b = 0; c = jd + 32082 } let d = INT((4 * c + 3) / 1461), e = c - INT((1461 * d) / 4), m = INT((5 * e + 2) / 153); return [e - INT((153 * m + 2) / 5) + 1, m + 3 - 12 * INT(m / 10), b * 100 + d - 4800 + INT(m / 10)] }
function NewMoon(k) { const T = k / 1236.85, T2 = T * T, T3 = T2 * T, dr = PI / 180; let Jd1 = 2415020.75933 + 29.53058868 * k + 0.0001178 * T2 - 0.000000155 * T3; Jd1 += 0.00033 * Math.sin((166.56 + 132.87 * T - 0.009173 * T2) * dr); const M = 359.2242 + 29.10535608 * k - 0.0000333 * T2 - 0.00000347 * T3, Mpr = 306.0253 + 385.81691806 * k + 0.0107306 * T2 + 0.00001236 * T3, F = 21.2964 + 390.67050646 * k - 0.0016528 * T2 - 0.00000239 * T3; let C1 = (0.1734 - 0.000393 * T) * Math.sin(M * dr) + 0.0021 * Math.sin(2 * dr * M); C1 = C1 - 0.4068 * Math.sin(Mpr * dr) + 0.0161 * Math.sin(dr * 2 * Mpr); C1 -= 0.0004 * Math.sin(dr * 3 * Mpr); C1 = C1 + 0.0104 * Math.sin(dr * 2 * F) - 0.0051 * Math.sin(dr * (M + Mpr)); C1 = C1 - 0.0074 * Math.sin(dr * (M - Mpr)) + 0.0004 * Math.sin(dr * (2 * F + M)); C1 = C1 - 0.0004 * Math.sin(dr * (2 * F - M)) - 0.0006 * Math.sin(dr * (2 * F + Mpr)); C1 = C1 + 0.0010 * Math.sin(dr * (2 * F - Mpr)) + 0.0005 * Math.sin(dr * (2 * Mpr + M)); const dt = T < -11 ? 0.001 + 0.000839 * T + 0.0002261 * T2 - 0.00000845 * T3 - 0.000000081 * T * T3 : -0.000278 + 0.000265 * T + 0.000262 * T2; return Jd1 + C1 - dt }
function SunLongitude(j) { const T = (j - 2451545.0) / 36525, T2 = T * T, dr = PI / 180; const M = 357.52910 + 35999.05030 * T - 0.0001559 * T2 - 0.00000048 * T * T2, L0 = 280.46645 + 36000.76983 * T + 0.0003032 * T2; let DL = (1.914600 - 0.004817 * T - 0.000014 * T2) * Math.sin(dr * M); DL += (0.019993 - 0.000101 * T) * Math.sin(dr * 2 * M) + 0.000290 * Math.sin(dr * 3 * M); let L = (L0 + DL) * dr; return L - PI * 2 * INT(L / (PI * 2)) }
const sunL = (d) => INT(SunLongitude(d - 0.5 - TZ / 24) / PI * 6);
const nmDay = (k) => INT(NewMoon(k) + 0.5 + TZ / 24);
function m11(yy) { const k = INT((jdFromDate(31, 12, yy) - 2415021) / 29.530588853); let nm = nmDay(k); if (sunL(nm) >= 9) nm = nmDay(k - 1); return nm }
function leapOff(a11) { const k = INT((a11 - 2415021.076998695) / 29.530588853 + 0.5); let last, i = 1, arc = sunL(nmDay(k + i)); do { last = arc; i++; arc = sunL(nmDay(k + i)) } while (arc != last && i < 14); return i - 1 }
function s2l(dd, mm, yy) { const dn = jdFromDate(dd, mm, yy), k = INT((dn - 2415021.076998695) / 29.530588853); let ms = nmDay(k + 1); if (ms > dn) ms = nmDay(k); let a11 = m11(yy), b11 = a11, ly; if (a11 >= ms) { ly = yy; a11 = m11(yy - 1) } else { ly = yy + 1; b11 = m11(yy + 1) } const ld = dn - ms + 1, diff = INT((ms - a11) / 29); let leap = 0, lm = diff + 11; if (b11 - a11 > 365) { const lo = leapOff(a11); if (diff >= lo) { lm = diff + 10; if (diff == lo) leap = 1 } } if (lm > 12) lm -= 12; if (lm >= 11 && diff < 4) ly -= 1; return [ld, lm, ly, leap] }

/* ===== Sự kiện của ngày mai ===== */
const honor = (p) => p.died ? (p.gen <= 2 ? (p.gender === "nu" ? "Cụ bà" : "Cụ ông") : (p.gender === "nu" ? "Bà" : "Ông")) : (p.gender === "nu" ? "Bà" : "Ông");
const p2 = (n) => String(n).padStart(2, "0");

function eventsFor(persons, tY, tM, tD) {
  const out = [];
  const [ld, lm, ly, leap] = s2l(tD, tM, tY);
  const nd = new Date(Date.UTC(tY, tM - 1, tD) + 86400000);
  const lastDay = s2l(nd.getUTCDate(), nd.getUTCMonth() + 1, nd.getUTCFullYear())[0] === 1;
  for (const p of persons) {
    if (!p.died) {
      if (p.born_d === tD && p.born_m === tM) {
        const age = p.born_y ? tY - p.born_y : null;
        out.push({ type: "bd", who: `${honor(p)} ${p.name}`, detail: age && age > 0 ? `tròn ${age} tuổi` : "", date: `${p2(tD)}/${p2(tM)}` });
      }
    } else if (!leap && p.died_d && p.died_m === lm && (p.died_d === ld || (p.died_d === 30 && ld === 29 && lastDay))) {
      const n = p.died_y ? ly - p.died_y : null;
      out.push({ type: "gio", who: `${honor(p)} ${p.name}`, detail: `${n && n > 0 ? "lần thứ " + n + " · " : ""}${p.died_d}/${p.died_m} âm lịch`, date: `${p2(tD)}/${p2(tM)}` });
    }
  }
  return out;
}

function makePayload(evs, dateKey) {
  if (evs.length === 1) {
    const e = evs[0];
    return { title: `Ngày mai ${e.type === "gio" ? "giỗ" : "sinh nhật"} ${e.who}`, body: `${e.detail ? e.detail + " · " : ""}${e.date}`, url: SITE, tag: "lecong-" + dateKey };
  }
  return {
    title: `Ngày mai có ${evs.length} sự kiện trong họ`,
    body: evs.map((e) => `${e.type === "gio" ? "Giỗ" : "Sinh nhật"} ${e.who}${e.detail ? " (" + e.detail + ")" : ""}`).join("\n"),
    url: SITE, tag: "lecong-" + dateKey,
  };
}

async function fetchAll(sb, table, cols) {
  const rows = []; let from = 0;
  while (true) {
    const { data, error } = await sb.from(table).select(cols).range(from, from + 999);
    if (error) throw new Error(error.message);
    rows.push(...data); if (data.length < 1000) break; from += 1000;
  }
  return rows;
}

async function send(sb, sub, payload) {
  try {
    await webpush.sendNotification({ endpoint: sub.endpoint, keys: { p256dh: sub.p256dh, auth: sub.auth } }, JSON.stringify(payload), { TTL: 6 * 3600, urgency: "high" });
    return "ok";
  } catch (e) {
    if (e.statusCode === 404 || e.statusCode === 410) { await sb.from("push_subscriptions").delete().eq("id", sub.id); return "gone"; }
    return "fail:" + (e.statusCode || e.message);
  }
}

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response(null, { headers: CORS });
  try {
    const sb = createClient(Deno.env.get("SUPABASE_URL"), Deno.env.get("SUPABASE_SERVICE_ROLE_KEY"));
    const { data: sec } = await sb.from("app_secrets").select("name,value");
    const S = Object.fromEntries((sec || []).map((r) => [r.name, r.value]));
    if (!S.vapid_public || !S.vapid_private) return json({ error: "Chưa cấu hình khóa thông báo" }, 500);
    webpush.setVapidDetails(SITE, S.vapid_public, S.vapid_private);

    let body = {}; if (req.method === "POST") { try { body = await req.json() } catch (_) { } }

    // Gửi thử cho chính người đang đăng nhập
    if (body.action === "test") {
      if (!/^[0-9a-f-]{36}$/i.test(String(body.token || ""))) return json({ error: "Phiên đăng nhập không hợp lệ" }, 401);
      const { data: ses } = await sb.from("sessions").select("user_id,expires_at").eq("token", body.token).maybeSingle();
      if (!ses || new Date(ses.expires_at) < new Date()) return json({ error: "Phiên đăng nhập đã hết hạn" }, 401);
      const { data: subs } = await sb.from("push_subscriptions").select("*").eq("user_id", ses.user_id);
      let sent = 0, failed = 0;
      for (const s of subs || []) {
        const r = await send(sb, s, { title: "Thông báo đã hoạt động", body: "Từ nay app sẽ nhắc ngày giỗ và sinh nhật vào 7 giờ sáng, trước 1 ngày.", url: SITE, tag: "lecong-test" });
        r === "ok" ? sent++ : failed++;
      }
      return json({ sent, failed });
    }

    // Chạy hằng ngày (chỉ máy chủ có mã bí mật mới gọi được)
    const key = req.headers.get("x-cron-secret");
    if (!key || key !== S.cron_secret) return json({ error: "unauthorized" }, 401);

    const nowVN = new Date(Date.now() + TZ * 3600 * 1000);
    let base = Date.UTC(nowVN.getUTCFullYear(), nowVN.getUTCMonth(), nowVN.getUTCDate());
    if (/^\d{4}-\d{2}-\d{2}$/.test(String(body.date || ""))) { const [y, m, d] = body.date.split("-").map(Number); base = Date.UTC(y, m - 1, d); }
    const tom = new Date(base + 86400000);
    const tY = tom.getUTCFullYear(), tM = tom.getUTCMonth() + 1, tD = tom.getUTCDate();
    const dateKey = `${tY}-${p2(tM)}-${p2(tD)}`;

    const persons = await fetchAll(sb, "persons", "id,name,gender,gen,born_d,born_m,born_y,died,died_d,died_m,died_y");
    const evs = eventsFor(persons, tY, tM, tD);
    const { data: subs } = await sb.from("push_subscriptions").select("*, app_users!inner(status)").eq("app_users.status", "active");

    if (body.dry) return json({ dateKey, events: evs, subscriptions: (subs || []).length });
    let sent = 0, failed = 0, gone = 0, skipped = 0;
    for (const s of subs || []) {
      const mine = evs.filter((e) => (e.type === "gio" ? s.gio : s.bd));
      if (!mine.length) { skipped++; continue; }
      const r = await send(sb, s, makePayload(mine, dateKey));
      r === "ok" ? sent++ : r === "gone" ? gone++ : failed++;
    }
    return json({ dateKey, events: evs.length, sent, failed, gone, skipped });
  } catch (e) {
    return json({ error: String(e && e.message || e) }, 500);
  }
});
