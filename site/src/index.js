// CrowdTale relay: Cloudflare Worker + one Durable Object per room.
//
// The game can only make HTTPS GET requests, so everything is a small GET
// command with strictly parsed parameters. A room holds up to 4 games and 8
// phone/browser voters plus the vote currently on screen. Replies echo `rid`
// so the game can match its async callbacks.

import { PAGE_HTML } from "./page.js";

const VERSION = 2;
// The first one is the default for rooms created without ?game=.
const GAMES = ["wolf"];
const MAX_GAME_PLAYERS = 4;
const MAX_PHONE_PLAYERS = 8;
const MAX_CHOICES = 8;
const MAX_CHOICE_TEXT = 160;
const MAX_NAME = 20;
const ROOM_TTL_MS = 6 * 60 * 60 * 1000; // room disappears 6 h after last change
const ACTIVE_MS = 2 * 60 * 1000; // a guest silent this long is shown as gone
// The host polls every 6-10 s and goes quiet while the game is minimized.
// After a minute voting is put on hold; after ten minutes the room closes.
const HOST_AWAY_MS = 60 * 1000;
const HOST_GONE_MS = 10 * 60 * 1000;
// During a vote the host polls every 0.75 s; a longer gap means the game
// is frozen, so the countdown stops.
const HOST_FROZEN_MS = 2500;
const HOST_WHERE = ["menu", "game", "paused"];
const CODE_ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ"; // no 0/O, 1/I/L
const CODE_LENGTH = 6;
const JOIN_FAILS_PER_MINUTE = 10;
const LINK_MAX_MESSAGE = 4000; // characters per game-to-game message
const LINK_MAX_PER_SECOND = 40;
const RECENT_RESULTS = 12;
const FORWARDED = ["id", "paused", "where", "token", "count", "seq", "index", "fallback", "name", "kind", "secs", "sid",
  "t0", "t1", "t2", "t3", "t4", "t5", "t6", "t7"];

// Per isolate, best effort.
const joinFails = new Map();

function reply(rid, status, body) {
  return new Response(JSON.stringify({ rid, ...body }), {
    status,
    headers: {
      "Content-Type": "application/json; charset=utf-8",
      "Cache-Control": "no-store",
      "X-Content-Type-Options": "nosniff",
    },
  });
}

function page() {
  return new Response(PAGE_HTML, {
    headers: {
      "Content-Type": "text/html; charset=utf-8",
      "Cache-Control": "no-cache",
      "X-Content-Type-Options": "nosniff",
      "X-Frame-Options": "DENY",
      "Referrer-Policy": "no-referrer",
      "Content-Security-Policy":
        "default-src 'none'; script-src 'unsafe-inline'; style-src 'unsafe-inline'; font-src data:; " +
        "connect-src 'self'; img-src data:; base-uri 'none'; form-action 'none'; frame-ancestors 'none'",
    },
  });
}

function randomCode() {
  let code = "";
  while (code.length < CODE_LENGTH) {
    const bytes = new Uint8Array(CODE_LENGTH);
    crypto.getRandomValues(bytes);
    for (const b of bytes) {
      // 248 = 8 * 31: rejecting above it keeps every character equally likely.
      if (b < 248 && code.length < CODE_LENGTH) code += CODE_ALPHABET[b % CODE_ALPHABET.length];
    }
  }
  return code;
}

function randomToken() {
  const bytes = new Uint8Array(16);
  crypto.getRandomValues(bytes);
  return [...bytes].map((b) => b.toString(16).padStart(2, "0")).join("");
}

function normalizeCode(raw) {
  if (typeof raw !== "string") return null;
  const code = raw.toUpperCase().replace(/[\s-]/g, "");
  if (code.length !== CODE_LENGTH) return null;
  for (const c of code) if (!CODE_ALPHABET.includes(c)) return null;
  return code;
}

function smallInt(raw, min, max) {
  if (typeof raw !== "string" || !/^\d{1,9}$/.test(raw)) return null;
  const n = Number(raw);
  return n >= min && n <= max ? n : null;
}

function cleanText(raw, max, pattern) {
  if (typeof raw !== "string") return "";
  const text = raw.normalize("NFC").replace(pattern, "").replace(/\s+/g, " ").trim();
  return [...text].slice(0, max).join("");
}

// Steam id, or "local-PORT" for the two-copies test setup.
function cleanSid(raw) {
  if (typeof raw !== "string") return "";
  return /^(\d{1,20}|local-\d{1,5})$/.test(raw) ? raw : "";
}

function cleanName(raw, fallback) {
  return cleanText(raw, MAX_NAME, /[^\p{L}\p{N} ._'-]/gu) || fallback;
}

function cleanChoice(raw) {
  // Brackets stay for action lines like "[threaten him]".
  return cleanText(raw, MAX_CHOICE_TEXT, /[^\p{L}\p{N}\p{Zs} .,;:!?'"()[\]\-…]/gu);
}

function tooManyJoinFails(ip) {
  const entry = joinFails.get(ip);
  return entry !== undefined && Date.now() - entry.start <= 60_000 && entry.count >= JOIN_FAILS_PER_MINUTE;
}

function noteJoinFail(ip) {
  const now = Date.now();
  const entry = joinFails.get(ip);
  if (!entry || now - entry.start > 60_000) joinFails.set(ip, { start: now, count: 1 });
  else entry.count++;
  if (joinFails.size > 5000) joinFails.clear();
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    const rid = smallInt(url.searchParams.get("rid") ?? "0", 0, 999999999) ?? 0;
    if (request.method !== "GET") return reply(rid, 405, { ok: false, error: "method not allowed" });
    if (url.search.length > 4096) return reply(rid, 414, { ok: false, error: "request too long" });

    const path = url.pathname;
    if (path === "/" || path === "/index.html") return page();
    if (path === "/v1/health") {
      const note = url.searchParams.get("note");
      if (note && env.DEBUG_NOTES) console.log("[game note]", note.slice(0, 300));
      return reply(rid, 200, { ok: true, version: VERSION });
    }

    if (path === "/v1/create") {
      for (let attempt = 0; attempt < 5; attempt++) {
        const code = randomCode();
        const room = env.ROOMS.get(env.ROOMS.idFromName(code));
        const inner = new URL("https://room/create");
        inner.searchParams.set("code", code);
        inner.searchParams.set("rid", String(rid));
        const name = url.searchParams.get("name");
        if (name !== null) inner.searchParams.set("name", name.slice(0, 64));
        const sid = url.searchParams.get("sid");
        if (sid !== null) inner.searchParams.set("sid", sid.slice(0, 32));
        const game = url.searchParams.get("game");
        if (game !== null) inner.searchParams.set("game", game.slice(0, 16));
        const res = await room.fetch(inner.toString());
        if (res.status !== 409) return res;
      }
      return reply(rid, 503, { ok: false, error: "could not allocate a room code" });
    }

    const allowed = ["/v1/check", "/v1/join", "/v1/state", "/v1/poll", "/v1/vote", "/v1/resolve", "/v1/applied", "/v1/leave", "/v1/kick", "/v1/pause", "/v1/link"];
    if (!allowed.includes(path)) return reply(rid, 404, { ok: false, error: "unknown endpoint" });

    const code = normalizeCode(url.searchParams.get("code"));
    if (!code) return reply(rid, 400, { ok: false, error: "invalid session code" });

    const ip = request.headers.get("CF-Connecting-IP") || "local";
    // check counts as a join so it can't be used to probe codes faster.
    const joining = path === "/v1/join" || path === "/v1/check";
    if (joining && tooManyJoinFails(ip)) {
      return reply(rid, 429, { ok: false, error: "too many attempts, wait a minute" });
    }

    const inner = new URL(`https://room${path}`);
    for (const key of FORWARDED) {
      const value = url.searchParams.get(key);
      if (value !== null) inner.searchParams.set(key, value.slice(0, 400));
    }
    inner.searchParams.set("code", code);
    inner.searchParams.set("rid", String(rid));
    const room = env.ROOMS.get(env.ROOMS.idFromName(code));
    if (path === "/v1/link") {
      return room.fetch(new Request(inner.toString(), { headers: request.headers }));
    }
    const res = await room.fetch(inner.toString());
    if (joining && res.status === 404) noteJoinFail(ip);
    // HttpGetAsync drops non-200 replies, so the game needs a 200 here.
    if (path === "/v1/check" && (res.status === 404 || res.status === 409)) {
      const body = await res.json();
      return reply(rid, 200, { ok: false, error: body.error });
    }
    return res;
  },
};

export class Room {
  constructor(ctx) {
    this.ctx = ctx;
    // state: { code, game, players: [{id, token, applied, name, kind, sid}], nextPoll, poll, recent, kicked }
    // poll:  { seq, count, texts[], votes{id: index}, order[id], result, closesAt, pausedAt }
    this.state = null;
    this.seen = new Map(); // id -> last request time, kept in memory only
    this.hostWhere = null;
  }

  touch(player) {
    const now = Date.now();
    if (player.id === 0) {
      // A frozen host shouldn't eat into the vote's time.
      const poll = this.state && this.state.poll;
      const last = this.seen.get(0);
      if (poll && poll.result === null && poll.closesAt && !poll.pausedAt && last && now - last > HOST_FROZEN_MS) {
        poll.closesAt += now - last;
        this.dirty = true;
      }
    }
    this.seen.set(player.id, now);
  }

  hostFrozenSince() {
    const poll = this.state && this.state.poll;
    const last = this.seen.get(0);
    if (!poll || poll.result !== null || !last) return null;
    const silent = Date.now() - last;
    // After a minute assume the scene moved on and let the vote expire.
    return silent > HOST_FROZEN_MS && silent < 60_000 ? last : null;
  }

  activePlayers() {
    const now = Date.now();
    return this.state.players.filter((p) => {
      if (p.id === 0) return true;
      const t = this.seen.get(p.id);
      return t === undefined || now - t < ACTIVE_MS;
    });
  }

  hostAway() {
    const t = this.seen.get(0);
    return t !== undefined && Date.now() - t > HOST_AWAY_MS;
  }

  hostGone() {
    const t = this.seen.get(0);
    return t !== undefined && Date.now() - t > HOST_GONE_MS;
  }

  async close() {
    await this.ctx.storage.deleteAll();
    this.state = false;
    this.seen.clear();
  }

  async load() {
    if (this.state === null) this.state = (await this.ctx.storage.get("room")) ?? false;
    return this.state;
  }

  async save() {
    await this.ctx.storage.put("room", this.state);
    await this.ctx.storage.setAlarm(Date.now() + ROOM_TTL_MS);
  }

  async alarm() {
    await this.ctx.storage.deleteAll();
    this.state = false;
  }

  player(token) {
    if (typeof token !== "string" || !/^[0-9a-f]{32}$/.test(token)) return null;
    return this.state.players.find((p) => p.token === token) ?? null;
  }

  nameOf(id) {
    const p = this.state.players.find((x) => x.id === id);
    return p ? { name: p.name, kind: p.kind } : { name: "Player", kind: "game" };
  }

  pollView(me) {
    const poll = this.state.poll;
    if (!poll) return null;
    const votes = new Array(poll.count).fill(0);
    for (const v of Object.values(poll.votes)) if (v >= 0 && v < poll.count) votes[v]++;
    const view = {
      seq: poll.seq,
      count: poll.count,
      votes,
      result: poll.result,
      texts: poll.texts,
      voters: poll.order.map((id) => this.nameOf(id)),
    };
    const frozen = this.hostFrozenSince();
    // Long overdue: the scene cancelled the choice.
    if (poll.result === null && poll.closesAt && !poll.pausedAt && !frozen && Date.now() > poll.closesAt + 15_000) {
      return null;
    }
    if (poll.closesAt) {
      const now = poll.pausedAt || frozen || Date.now();
      view.remaining = Math.max(0, Math.round((poll.closesAt - now) / 1000));
    }
    if (poll.pausedAt || frozen) view.paused = true;
    if (me && poll.votes[me.id] !== undefined) view.mine = poll.votes[me.id];
    return view;
  }

  stateView(me) {
    const active = this.activePlayers();
    return {
      ok: true,
      code: this.state.code,
      game: this.state.game || GAMES[0],
      id: me.id,
      role: me.id === 0 ? "host" : me.kind === "game" ? "guest" : me.kind,
      players: active.length,
      names: active.map((p) => {
        const entry = { id: p.id, name: p.name, host: p.id === 0, kind: p.kind };
        if (me.kind === "game" && p.kind === "game" && p.sid) entry.sid = p.sid;
        return entry;
      }),
      limit: MAX_GAME_PLAYERS,
      hostWhere: this.hostAway() ? "away" : this.hostFrozenSince() ? "paused" : this.hostWhere,
      applied: me.applied,
      poll: this.pollView(me),
      recent: me.kind === "game" ? (this.state.recent || []).filter((r) => r.seq > me.applied) : undefined,
    };
  }

  async fetch(request) {
    const url = new URL(request.url);
    const q = url.searchParams;
    const rid = Number(q.get("rid")) || 0;
    const room = await this.load();

    if (url.pathname === "/create") {
      if (room) return reply(rid, 409, { ok: false, error: "code in use" });
      const host = { id: 0, token: randomToken(), applied: 0, name: cleanName(q.get("name"), "Host"), kind: "game", sid: cleanSid(q.get("sid")) };
      const game = GAMES.includes(q.get("game")) ? q.get("game") : GAMES[0];
      this.state = { code: q.get("code"), game, players: [host], nextPoll: 0, poll: null };
      this.seen.clear();
      this.touch(host);
      await this.save();
      return reply(rid, 200, { ...this.stateView(host), token: host.token });
    }

    if (room && this.hostGone()) await this.close();
    if (!this.state) return reply(rid, 404, { ok: false, error: "session not found" });

    if (url.pathname === "/v1/check") {
      const raw = q.get("kind");
      const kind = raw === "phone" || raw === "web" ? raw : "game";
      const voter = (k) => k === "phone" || k === "web";
      const active = this.activePlayers();
      const sameKind = active.filter((p) => (voter(kind) ? voter(p.kind) : p.kind === kind)).length;
      const limit = voter(kind) ? MAX_PHONE_PLAYERS : MAX_GAME_PLAYERS;
      if (sameKind >= limit) return reply(rid, 409, { ok: false, error: "session is full" });
      return reply(rid, 200, { ok: true });
    }

    if (url.pathname === "/v1/join") {
      const raw = q.get("kind");
      const kind = raw === "phone" || raw === "web" ? raw : "game";
      const active = new Set(this.activePlayers());
      this.state.players = this.state.players.filter((p) => p.id === 0 || active.has(p));
      const voter = (k) => k === "phone" || k === "web";
      const sameKind = this.state.players.filter((p) => (voter(kind) ? voter(p.kind) : p.kind === kind)).length;
      const limit = voter(kind) ? MAX_PHONE_PLAYERS : MAX_GAME_PLAYERS;
      if (sameKind >= limit) return reply(rid, 409, { ok: false, error: "session is full" });
      const used = new Set(this.state.players.map((p) => p.id));
      let id = voter(kind) ? 10 : 1;
      while (used.has(id)) id++;
      // Late joiners must not replay votes that were already decided.
      const applied = this.state.poll ? this.state.poll.seq : 0;
      const fallback = kind === "phone" ? `Phone ${id - 9}` : kind === "web" ? `Web ${id - 9}` : `Player ${id + 1}`;
      const guest = { id, token: randomToken(), applied, name: cleanName(q.get("name"), fallback), kind,
        sid: kind === "game" ? cleanSid(q.get("sid")) : "" };
      this.state.players.push(guest);
      this.touch(guest);
      await this.save();
      return reply(rid, 200, { ...this.stateView(guest), token: guest.token });
    }

    const me = this.player(q.get("token"));
    if (!me) {
      const removed = (this.state.kicked || []).includes(q.get("token"));
      return reply(rid, 403, { ok: false, error: removed ? "removed by the host" : "not a member of this session" });
    }
    this.touch(me);
    if (this.dirty) {
      this.dirty = false;
      await this.save();
    }

    switch (url.pathname) {
      case "/v1/state": {
        const where = q.get("where");
        if (me.id === 0 && HOST_WHERE.includes(where)) this.hostWhere = where;
        return reply(rid, 200, this.stateView(me));
      }

      case "/v1/poll": {
        if (me.id !== 0) return reply(rid, 403, { ok: false, error: "only the host opens votes" });
        const count = smallInt(q.get("count"), 2, MAX_CHOICES);
        if (count === null) return reply(rid, 400, { ok: false, error: "2-8 choices required" });
        const texts = [];
        for (let i = 0; i < count; i++) texts.push(cleanChoice(q.get(`t${i}`)));
        const secs = smallInt(q.get("secs") ?? "", 1, 600);
        this.state.nextPoll++;
        this.state.poll = {
          seq: this.state.nextPoll, count, texts, votes: {}, order: [], result: null,
          closesAt: secs ? Date.now() + secs * 1000 : null,
        };
        await this.save();
        return reply(rid, 200, { ok: true, seq: this.state.nextPoll });
      }

      case "/v1/vote": {
        const poll = this.state.poll;
        const seq = smallInt(q.get("seq"), 1, 999999999);
        const index = smallInt(q.get("index"), 0, MAX_CHOICES - 1);
        if (!poll || seq !== poll.seq || index === null || index >= poll.count || poll.result !== null) {
          return reply(rid, 400, { ok: false, error: "invalid or closed vote" });
        }
        if (me.id !== 0 && this.hostAway()) return reply(rid, 409, { ok: false, error: "host away" });
        // Hidden choices arrive with empty text.
        if (poll.texts.some((t) => t) && !poll.texts[index]) {
          return reply(rid, 400, { ok: false, error: "invalid or closed vote" });
        }
        if (poll.votes[me.id] === undefined) poll.order.push(me.id);
        poll.votes[me.id] = index;
        await this.save();
        // The page wants the new counts right away.
        if (q.get("view") === "1") return reply(rid, 200, this.stateView(me));
        return reply(rid, 200, { ok: true });
      }

      case "/v1/resolve": {
        if (me.id !== 0) return reply(rid, 403, { ok: false, error: "only the host closes votes" });
        const poll = this.state.poll;
        const seq = smallInt(q.get("seq"), 1, 999999999);
        if (!poll || seq !== poll.seq) return reply(rid, 400, { ok: false, error: "poll sequence mismatch" });
        if (poll.result !== null) return reply(rid, 200, { ok: true, result: poll.result });
        const counts = new Array(poll.count).fill(0);
        for (const v of Object.values(poll.votes)) counts[v]++;
        const high = Math.max(...counts);
        let result;
        if (high === 0) {
          const fallback = smallInt(q.get("fallback"), 0, poll.count - 1);
          if (fallback === null) return reply(rid, 400, { ok: false, error: "no votes yet" });
          result = fallback;
        } else {
          const hostVote = poll.votes[0];
          // Ties go to the host.
          result = hostVote !== undefined && counts[hostVote] === high ? hostVote : counts.indexOf(high);
        }
        poll.result = result;
        poll.closesAt = null;
        poll.pausedAt = null;
        // For games that reach the choice after the next vote has opened.
        this.state.recent = [...(this.state.recent || []), { seq: poll.seq, count: poll.count, result }].slice(-RECENT_RESULTS);
        await this.save();
        return reply(rid, 200, { ok: true, result });
      }

      case "/v1/applied": {
        const seq = smallInt(q.get("seq"), 1, 999999999);
        if (seq === null) return reply(rid, 400, { ok: false, error: "invalid poll sequence" });
        if (seq > me.applied) {
          me.applied = seq;
          await this.save();
        }
        return reply(rid, 200, { ok: true, applied: me.applied });
      }

      case "/v1/kick": {
        if (me.id !== 0) return reply(rid, 403, { ok: false, error: "only the host removes players" });
        const id = smallInt(q.get("id"), 1, 99);
        const target = this.state.players.find((p) => p.id === id);
        if (!target) return reply(rid, 404, { ok: false, error: "player not found" });
        this.state.players = this.state.players.filter((p) => p !== target);
        this.state.kicked = [...(this.state.kicked || []), target.token].slice(-16);
        if (this.state.poll) delete this.state.poll.votes[id];
        if (this.state.poll) this.state.poll.order = this.state.poll.order.filter((x) => x !== id);
        this.seen.delete(id);
        await this.save();
        return reply(rid, 200, { ok: true });
      }

      case "/v1/pause": {
        if (me.id !== 0) return reply(rid, 403, { ok: false, error: "only the host pauses" });
        const poll = this.state.poll;
        const paused = q.get("paused") === "1";
        if (poll && poll.result === null) {
          if (paused && !poll.pausedAt) poll.pausedAt = Date.now();
          if (!paused && poll.pausedAt) {
            if (poll.closesAt) poll.closesAt += Date.now() - poll.pausedAt;
            poll.pausedAt = null;
          }
          await this.save();
        }
        return reply(rid, 200, { ok: true });
      }

      case "/v1/leave": {
        if (me.id === 0) {
          this.closeLinks();
          await this.close();
        } else {
          this.state.players = this.state.players.filter((p) => p !== me);
          this.closeLinks(me.id);
          await this.save();
        }
        return reply(rid, 200, { ok: true });
      }

      case "/v1/link": {
        // Fallback game-to-game channel for when Steam P2P isn't available.
        if (me.kind !== "game") return reply(rid, 403, { ok: false, error: "games only" });
        if ((request.headers.get("Upgrade") || "").toLowerCase() !== "websocket") {
          return reply(rid, 426, { ok: false, error: "websocket required" });
        }
        this.closeLinks(me.id);
        const pair = new WebSocketPair();
        this.ctx.acceptWebSocket(pair[1], [`p${me.id}`]);
        return new Response(null, { status: 101, webSocket: pair[0] });
      }
    }
    return reply(rid, 404, { ok: false, error: "unknown endpoint" });
  }

  closeLinks(id) {
    const sockets = id === undefined ? this.ctx.getWebSockets() : this.ctx.getWebSockets(`p${id}`);
    for (const ws of sockets) {
      try { ws.close(1000, "left"); } catch {}
    }
  }

  async webSocketMessage(ws, message) {
    // "." is a keep-alive
    if (typeof message !== "string" || message === "." || message.length > LINK_MAX_MESSAGE) return;
    const tag = this.ctx.getTags(ws)[0] || "";
    const id = Number(tag.slice(1));
    const now = Date.now();
    const rate = this.linkRate || (this.linkRate = new Map());
    const entry = rate.get(id);
    if (!entry || now - entry.start > 1000) rate.set(id, { start: now, count: 1 });
    else if (++entry.count > LINK_MAX_PER_SECOND) return;
    const room = await this.load();
    if (!room || !this.state.players.some((p) => p.id === id && p.kind === "game")) {
      try { ws.close(1008, "not a member"); } catch {}
      return;
    }
    if (id === 0) this.touch({ id: 0 });
    const out = `${id}\t${message}`;
    for (const other of this.ctx.getWebSockets()) {
      if (other === ws) continue;
      try { other.send(out); } catch {}
    }
  }

  async webSocketClose(ws, code) {
    try { ws.close(code === 1005 ? 1000 : code, "bye"); } catch {}
  }

  async webSocketError(ws) {
    try { ws.close(1011, "error"); } catch {}
  }
}
