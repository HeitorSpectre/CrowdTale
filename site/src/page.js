// The voting page served at "/". Fonts and images are inlined from assets.js,
// so the page makes no third-party requests. Anything coming from the server
// or other players is written with textContent, never as HTML.
import { DAMASK, DIVIDER, FONT_FACES } from "./assets.js";
import { LANGUAGES, TEXTS } from "./i18n.js";

export const PAGE_HTML = `<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1, viewport-fit=cover">
<meta name="theme-color" content="#1a0711">
<title>CrowdTale</title>
<style>/*FONT_FACES*/</style>
<style>
  :root {
    --wall: #0f0b0d; --wall-2: #2b0d14;
    --frame: #3b2a31; --fill: #17111a;
    --title: #ffffff; --menu: #e6354f; --menu-hi: #ffffff; --text: #f4eef0; --muted: #b9abb0;
    --hud: #8cd9ff;
    --c0: #3cc8e8; --c1: #f2c94c; --c2: #e8475a; --c3: #52c98a;
    --c4: #b07ce8; --c5: #f08a3c; --c6: #e86fb7; --c7: #d9d2c4;
    --serif: "Josefin Sans", system-ui, sans-serif;
    --sans: "Josefin Sans", system-ui, sans-serif;
  }
  * { box-sizing: border-box; -webkit-tap-highlight-color: transparent; }
  html { background: var(--wall); }
  body {
    margin: 0; min-height: 100dvh; color: var(--text); font-family: var(--sans);
    background:
      radial-gradient(70% 40% at 50% 0%, #7a142a66 0%, transparent 75%),
      radial-gradient(60% 50% at 0% 100%, #3a0d1a55 0%, transparent 70%),
      repeating-linear-gradient(135deg, #ffffff05 0 2px, transparent 2px 14px),
      linear-gradient(180deg, var(--wall-2), var(--wall) 55%);
    background-attachment: fixed;
  }
  main { position: relative; z-index: 1; max-width: 480px; margin: 0 auto; padding: 58px 16px 48px; }
  header { text-align: center; margin-bottom: 22px; }
  .logo { display: block; width: min(300px, 78%); height: auto; margin: 0 auto; filter: drop-shadow(0 10px 24px #00000066); }
  .tagline { margin-top: 2px; font-size: 13px; font-weight: 600; letter-spacing: .3em; text-transform: uppercase; color: var(--muted); }
  h1 { font-family: var(--serif); font-weight: 400; color: var(--title); font-size: 42px; letter-spacing: .08em; text-transform: uppercase; margin: 6px 0 2px; }
  .divider { display: block; position: relative; height: 14px; margin: 14px auto 0; width: min(300px, 80%);
    background: linear-gradient(90deg, transparent, #ffffff40 20%, #ffffff40 80%, transparent) center / 100% 1px no-repeat; }
  .divider::after { content: ""; position: absolute; left: 50%; top: 50%; width: 10px; height: 10px;
    transform: translate(-50%, -50%) rotate(45deg); border: 2px solid #fff;
    background: conic-gradient(from -45deg, #e8b425 0 25%, #c8283c 0 50%, #5a9a2e 0 75%, #2f87c8 0); }

  .frame { position: relative; border-radius: 16px; padding: 1px; background: linear-gradient(180deg, #e6354f, #ffffff1f 30%, #ffffff12); }
  .frame > .in { border-radius: 15px; background: linear-gradient(180deg, #221820, var(--fill) 60%); padding: 22px 20px; }
  h2 { font-family: var(--serif); font-weight: 600; color: var(--title); text-align: center; font-size: 24px;
    letter-spacing: .06em; margin: 0; text-transform: uppercase; }
  .sub { text-align: center; color: var(--muted); font-size: 15px; margin: 12px 0 0; line-height: 1.45; }

  label { display: block; font-size: 12px; font-weight: 600; letter-spacing: .22em; color: var(--muted); margin: 20px 0 4px; text-transform: uppercase; }
  input {
    width: 100%; font: inherit; font-size: 22px; color: var(--menu-hi); background: transparent; outline: none;
    border: 0; border-bottom: 1px solid #ffffff33; padding: 8px 2px; border-radius: 0;
  }
  input::placeholder { color: #7c6273; }
  input:-webkit-autofill, input:-webkit-autofill:hover, input:-webkit-autofill:focus, input:autofill {
    -webkit-text-fill-color: var(--menu-hi); caret-color: var(--menu-hi);
    -webkit-box-shadow: 0 0 0 60px var(--fill) inset; box-shadow: 0 0 0 60px var(--fill) inset;
    transition: background-color 600000s 0s, color 600000s 0s; font-size: 22px; }
  input:focus { border-bottom-color: var(--menu); }
  #code { text-transform: uppercase; letter-spacing: .32em; text-align: center; }

  .menu {
    display: block; width: 100%; background: none; border: 0; cursor: pointer; padding: 10px 0; text-align: center;
    font-family: var(--sans); font-size: 26px; font-weight: 400; letter-spacing: .04em; text-transform: uppercase;
    color: var(--menu); transition: color .15s, text-shadow .15s;
  }
  .menu:hover, .menu:focus-visible { color: var(--menu-hi); text-shadow: 0 0 14px #c42a4466; outline: none; }
  .menu:disabled { opacity: .45; }
  .menu.small { font-size: 16px; padding: 4px 0; width: auto; }
  #joinBtn { margin-top: 10px; padding: 12px 0 9px; border-radius: 12px; background: linear-gradient(180deg, #ef4b63, #c41f3a);
    color: #fff; font-weight: 600; font-size: 22px; letter-spacing: .12em; box-shadow: 0 6px 18px -6px #e6354f99; }
  #joinBtn:hover, #joinBtn:focus-visible { text-shadow: none; filter: brightness(1.08); }
  .error { color: #ff8fa3; min-height: 20px; margin-top: 10px; font-size: 15px; text-align: center; }

  .bar { display: flex; align-items: baseline; justify-content: space-between; margin: 0 2px 6px; }
  .room { font-size: 22px; color: var(--title); letter-spacing: .04em; text-transform: uppercase; }
  .players { list-style: none; margin: 4px 2px 22px; padding: 0; }
  .players li { font-size: 18px; font-weight: 600; color: var(--text); text-transform: uppercase; letter-spacing: .03em; padding: 3px 0; }
  .players li .tag { color: var(--muted); font-size: 14px; margin-left: 8px; }
  .players li.voted::after { content: "  \\2022  " attr(data-voted); color: var(--c3); font-size: 13px; letter-spacing: .12em; text-transform: uppercase; }

  .waiting { text-align: center; }
  .diamond { width: 12px; height: 12px; margin: 16px auto 4px; background: var(--frame); transform: rotate(45deg);
    animation: glow 1.8s ease-in-out infinite; }
  @keyframes glow { 50% { background: var(--menu); box-shadow: 0 0 14px var(--menu); } }

  .vote-head { display: flex; align-items: baseline; justify-content: space-between; gap: 10px; margin-bottom: 8px; }
  .vote-head h2 { text-align: left; font-size: 22px; }
  .count { color: var(--muted); font-size: 14px; white-space: nowrap; }
  .timer { height: 3px; background: #2a1528; margin: 0 0 16px; }
  .timer i { display: block; height: 100%; width: 100%; background: var(--menu); transition: width 1s linear; }

  /* Same colours as the game's vote markers. */
  .choices { display: grid; gap: 10px; }
  .choice {
    position: relative; width: 100%; text-align: left; cursor: pointer; border: 0; padding: 14px 54px 16px 56px;
    min-height: 60px; background: linear-gradient(90deg, #000000cc, #0000008c); color: #fff;
    font-family: var(--sans); font-size: 19px; line-height: 1.3; box-shadow: inset 3px 0 0 var(--c);
  }
  .choice .key {
    position: absolute; left: 14px; top: 50%; transform: translateY(-50%) rotate(45deg); width: 24px; height: 24px;
    background: var(--c); box-shadow: 0 0 10px var(--c);
  }
  .choice .key b { display: grid; place-items: center; width: 100%; height: 100%; transform: rotate(-45deg);
    color: #120610; font-size: 13px; font-weight: 600; }
  .choice .pct { position: absolute; right: 12px; top: 50%; transform: translateY(-50%); color: var(--muted); font-size: 15px; }
  .choice .fill { position: absolute; left: 0; bottom: 0; height: 3px; width: 0; background: var(--c); transition: width .5s ease; }
  .choice.mine { box-shadow: inset 3px 0 0 var(--c), inset 0 0 0 1px var(--c), 0 0 18px -4px var(--c); }
  .choice.mine .pct, .choice.win .pct { color: #fff; }
  .choice.win { color: var(--c); box-shadow: inset 0 0 0 2px var(--c), 0 0 22px -2px var(--c); }
  .choice.lose { opacity: .5; }
  .choice:disabled { cursor: default; }
  .status { text-align: center; margin-top: 16px; color: var(--muted); min-height: 22px; font-size: 15px; }
  .status.good { color: var(--c3); }
  .status.done { font-family: var(--serif); color: var(--title); font-size: 18px; letter-spacing: .04em; }

  .toasts { position: fixed; left: 0; top: 14px; display: grid; gap: 6px; pointer-events: none; z-index: 5; }
  .toast {
    display: flex; align-items: center; gap: 10px; padding: 9px 26px 9px 14px; color: var(--hud);
    font-size: 14px; letter-spacing: .1em; text-transform: uppercase;
    background: linear-gradient(90deg, #000000dd 60%, #00000000); animation: in .3s ease-out, out .35s ease-in 2.6s forwards;
  }
  .toast::before { content: ""; width: 9px; height: 9px; background: var(--hud); transform: rotate(45deg); box-shadow: 0 0 8px var(--hud); }
  @keyframes in { from { transform: translateX(-16px); opacity: 0; } }
  @keyframes out { to { transform: translateX(-16px); opacity: 0; } }
  .plate { background: #110c10e6; padding: 14px 12px 16px; border-radius: 16px; box-shadow: 0 0 0 1px #ffffff14; }
  .choice { text-shadow: 0 1px 2px #000; }
  .legal { margin-top: 40px; text-align: center; color: #a58e9d; font-size: 12px; line-height: 1.55; }
  .legal p { margin: 10px 0 0; }
  .legal strong { color: var(--muted); font-weight: 600; }
  .langs { display: flex; justify-content: center; gap: 4px; margin-top: 12px; }
  .langs button { background: none; border: 0; cursor: pointer; padding: 6px 8px; font-family: var(--sans);
    font-size: 13px; letter-spacing: .16em; color: var(--muted); }
  .langs button[aria-pressed="true"] { color: var(--menu); text-shadow: 0 0 10px #ff547066; }

  /* ---- per-game themes ---- */
  .bg-game { position: fixed; inset: 0; z-index: 0; opacity: 0; pointer-events: none; transition: opacity 1.4s ease;
    background:
      linear-gradient(180deg, #0000004d, #000000a6),
      radial-gradient(90% 60% at 85% 0%, #5a163680 0%, transparent 70%),
      url("\${DAMASK}") center top / 112px repeat,
      linear-gradient(180deg, #24081a, #12040b); }
  body, .frame, .frame > .in, .plate, h2, .room, .players li, label, .menu, .count, .status, .legal, .sub { transition: color .9s, background .9s, border-color .9s, box-shadow .9s; }
  header .tagline, header .divider { max-height: 40px; transition: opacity .7s, max-height .9s, margin .9s; }
  .gamehead { max-height: 0; opacity: 0; overflow: hidden; transform: translateY(14px); transition: max-height .9s, opacity .9s .25s, transform .9s .25s; }
  .gamekicker { font-weight: 400; letter-spacing: .34em; font-size: 12px; color: #cdb3c4; text-transform: uppercase; }
  .gamehead h1 { font-family: "Marcellus", Georgia, serif; font-weight: 400; color: #e7a6df; font-size: 42px; letter-spacing: .08em; text-transform: uppercase; margin: 6px 0 2px; }
  .gamedivider { display: block; height: 12px; margin: 6px auto 0; width: min(320px, 80%); background: url("\${DIVIDER}") center / contain no-repeat; }

  body.theme-wolf {
    --frame: #9a52a1; --fill: #0d050d; --title: #e7a6df; --menu: #ff5470; --text: #f6ecf2; --muted: #cdb3c4;
    --serif: "Marcellus", Georgia, serif; --sans: "Josefin Sans", system-ui, sans-serif;
  }
  body.theme-wolf .bg-game { opacity: 1; }
  body.theme-wolf header .tagline, body.theme-wolf header .divider { opacity: 0; max-height: 0; margin-top: 0; overflow: hidden; }
  body.theme-wolf .gamehead { max-height: 40px; opacity: 1; transform: none; margin-top: 2px; }
  body.theme-wolf .frame { border-radius: 0; background: var(--frame);
    --n: 10px; clip-path: polygon(var(--n) 0, calc(100% - var(--n)) 0, calc(100% - var(--n)) var(--n), 100% var(--n),
      100% calc(100% - var(--n)), calc(100% - var(--n)) calc(100% - var(--n)), calc(100% - var(--n)) 100%,
      var(--n) 100%, var(--n) calc(100% - var(--n)), 0 calc(100% - var(--n)), 0 var(--n), var(--n) var(--n)); padding: 2px; }
  body.theme-wolf .frame > .in { border-radius: 0; background: radial-gradient(120% 100% at 50% 0%, #1d0d1d, var(--fill) 70%);
    --n: 9px; clip-path: polygon(var(--n) 0, calc(100% - var(--n)) 0, calc(100% - var(--n)) var(--n), 100% var(--n),
      100% calc(100% - var(--n)), calc(100% - var(--n)) calc(100% - var(--n)), calc(100% - var(--n)) 100%,
      var(--n) 100%, var(--n) calc(100% - var(--n)), 0 calc(100% - var(--n)), 0 var(--n), var(--n) var(--n)); }
  body.theme-wolf h2 { font-weight: 400; letter-spacing: .05em; }
  body.theme-wolf .plate { border-radius: 0; background: #0a0309d9; box-shadow: 0 0 0 1px #9a52a133; }
  body.theme-wolf .players li { font-weight: 400; font-size: 19px; }
  body.theme-wolf label { color: var(--title); }
  body.theme-wolf .legal .divider { height: 12px; background: url("\${DIVIDER}") center / contain no-repeat; }
  body.theme-wolf .legal .divider::after { display: none; }
  /* Circle reveal when entering/leaving a session (see morph()). Without
     view transitions the plain cross-fade above is used. */
  .logo { view-transition-name: ct-logo; }
  html.vt *, html.vt *::before, html.vt *::after { transition: none !important; }
  ::view-transition-old(root), ::view-transition-new(root) { animation: none; mix-blend-mode: normal; }
  html.vt-out::view-transition-old(root) { z-index: 2; }
  ::view-transition-group(ct-logo) { z-index: 5; animation-duration: .9s; }
  html.vt::view-transition-old(ct-logo) { display: none; }
  html.vt::view-transition-new(ct-logo) { animation: ct-stamp 1s cubic-bezier(.2,.8,.2,1) both; }
  @keyframes ct-stamp { 0% { transform: none; } 38% { transform: rotate(-5deg) scale(1.07); } 72% { transform: rotate(1.5deg) scale(.985); } 100% { transform: none; } }
  .vt-ring { position: fixed; z-index: 4; pointer-events: none; border-radius: 50%; border: 2px solid #ffd3de;
    box-shadow: 0 0 34px 8px #ff547099, inset 0 0 60px 14px #ff547077; }
  body.theme-wolf .gamedivider { animation: ct-draw .8s .75s cubic-bezier(.2,.8,.2,1) both; }
  @keyframes ct-draw { from { transform: scaleX(0); opacity: 0; } }
  [hidden] { display: none !important; }
  @media (prefers-reduced-motion: reduce) { * { animation: none !important; transition: none !important; } }
</style>
</head>
<body>
<div class="bg-game" aria-hidden="true"></div>
<div class="toasts" id="toasts" aria-live="polite"></div>
<main>
  <header>
    <svg class="logo" viewBox="-8 0 346 250" role="img" aria-label="CrowdTale">
      <g transform="rotate(3 173.0 125.0)">
        <path d="M32 18 H272 Q286 18 286 32 V172 Q286 186 272 186 L228 186 L264 232 L190 186 H32 Q18 186 18 172 V32 Q18 18 32 18 Z" transform="translate(5 7)" fill="#000000" opacity=".28"/>
        <path d="M32 18 H272 Q286 18 286 32 V172 Q286 186 272 186 L228 186 L264 232 L190 186 H32 Q18 186 18 172 V32 Q18 18 32 18 Z" fill="#ffffff"/>
        <path d="M76 49 C70 41 48 38 47 62.0 C48 86 70 83 76 75 M87 84 L87 41 L103 41 C116 41 116 63.0 103 63.0 L87 63.0 M103 63.0 L115 84 M143.0 41 C120 41 120 83 143.0 83 C166 83 166 41 143.0 41 Z M171 41 L181.5 83 L192.0 52 L202.5 83 L213 41 M224 41 L224 83 L235.0 83 C254 83 254 41 235.0 41 Z" fill="none" stroke="#5d5d68" stroke-width="5.2" stroke-linecap="square" stroke-linejoin="miter"/>
        <path d="M44 98 H94 V115 H77.5 V164 H60.5 V115 H44 Z M100 164 L120 98 H140 L160 164 H142 L139 150 H121 L118 164 Z M125.5 137 H134.5 L130 115 Z M166 98 H183 V148 H206 V164 H166 Z M212 98 H252 V113 H229 V123.5 H247 V138.5 H229 V149 H252 V164 H212 Z" fill="#a3192e" fill-rule="evenodd"/>
        <path d="M282 28 L252 28 L282 -2 Z" fill="#2f87c8"/><path d="M282 28 L282 -2 L312 28 Z" fill="#e8b425"/><path d="M282 28 L312 28 L282 58 Z" fill="#c8283c"/><path d="M282 28 L282 58 L252 28 Z" fill="#5a9a2e"/><path d="M252 28 L312 28 M282 -2 L282 58" stroke="#ffffff" stroke-width="3"/><path d="M252 28 L282 -2 L312 28 L282 58 Z" fill="none" stroke="#ffffff" stroke-width="5" stroke-linejoin="round"/>
      </g>
    </svg>
    <div class="tagline" data-i18n="tagline"></div>
    <span class="divider" aria-hidden="true"></span>
    <div class="gamehead" id="gameHead" aria-hidden="true">
      <span class="gamedivider"></span>
    </div>
    <nav class="langs" id="langs" aria-label="Language"></nav>
  </header>

  <section id="join">
    <div class="frame"><div class="in">
      <h2 data-i18n="joinTitle"></h2>
      <label for="code" data-i18n="code"></label>
      <input id="code" maxlength="7" autocomplete="off" autocapitalize="characters" spellcheck="false" placeholder="ABC-123">
      <label for="name" data-i18n="name"></label>
      <input id="name" maxlength="20" autocomplete="nickname" placeholder="Bigby">
      <div class="error" id="joinErr" role="alert"></div>
      <button class="menu" id="joinBtn" data-i18n="join"></button>
    </div></div>
    <p class="sub" data-i18n-html="hostHint"></p>
  </section>

  <section id="room" class="plate" hidden>
    <div class="bar">
      <div class="room"><span data-i18n="session"></span> <span id="roomCode"></span></div>
      <button class="menu small" id="leaveBtn" data-i18n="leave"></button>
    </div>
    <ul class="players" id="players"></ul>

    <div id="idle" class="frame"><div class="in waiting">
      <h2 id="idleTitle"></h2>
      <div class="diamond" aria-hidden="true"></div>
      <p class="sub" id="idleText"></p>
    </div></div>

    <div id="vote" hidden>
      <div class="vote-head"><h2 id="voteTitle"></h2><span class="count" id="voteCount"></span></div>
      <div class="timer" id="timerBar" hidden><i id="timerFill"></i></div>
      <div class="choices" id="choices"></div>
      <div class="status" id="voteStatus"></div>
    </div>
  </section>

  <footer class="legal">
    <span class="divider" aria-hidden="true"></span>
    <p id="legal1" data-i18n-html="legal1"></p>
    <p id="legal2" data-i18n-html="legal2"></p>
    <p data-i18n-html="legal3"></p>
  </footer>
</main>
<script>
(() => {
  const $ = (id) => document.getElementById(id);
  const TEXTS = /*TEXTS*/;
  const LANGUAGES = /*LANGUAGES*/;
  let lang = "en";
  const t = (key, vars) => String(TEXTS[lang][key] || TEXTS.en[key] || key)
    .replace(/\\{(\\w+)\\}/g, (_, k) => (vars && vars[k] !== undefined ? String(vars[k]) : ""));
  const ALPHABET = "23456789ABCDEFGHJKMNPQRSTUVWXYZ";
  let session = null; // { code, token }
  let rid = 1;
  let timer = null;
  let lastSeq = 0;
  let lastResultSeq = 0;
  let knownPlayers = null; // id -> name, for the join/leave toasts
  let knownVoters = 0;
  let timerStart = null;
  let resultShownAt = 0;
  // Bumped on every vote so a state request that was already in flight
  // doesn't redraw the old vote.
  let voteGen = 0;

  const store = {
    get(k) { try { return sessionStorage.getItem(k) || localStorage.getItem(k); } catch { return null; } },
    set(k, v, persist) { try { (persist ? localStorage : sessionStorage).setItem(k, v); } catch {} },
    del(k) { try { sessionStorage.removeItem(k); } catch {} },
  };

  let lastState = null;
  function applyLanguage(next) {
    lang = LANGUAGES.includes(next) ? next : "en";
    document.documentElement.lang = lang;
    for (const el of document.querySelectorAll("[data-i18n]")) el.textContent = t(el.dataset.i18n);
    for (const el of document.querySelectorAll("[data-i18n-html]")) el.innerHTML = t(el.dataset.i18nHtml);
    $("langs").setAttribute("aria-label", t("lang"));
    for (const b of $("langs").children) b.setAttribute("aria-pressed", String(b.dataset.lang === lang));
    if (lastState) { knownPlayers = null; render(lastState, true); }
  }
  for (const code of LANGUAGES) {
    const b = document.createElement("button");
    b.type = "button";
    b.dataset.lang = code;
    b.textContent = code.toUpperCase();
    b.addEventListener("click", () => { store.set("crowdtale.lang", code, true); applyLanguage(code); });
    $("langs").appendChild(b);
  }

  function toast(text) {
    const el = document.createElement("div");
    el.className = "toast";
    el.textContent = text;
    $("toasts").appendChild(el);
    setTimeout(() => el.remove(), 3100);
  }

  function normalize(raw) {
    const code = String(raw || "").toUpperCase().replace(/[\\s-]/g, "");
    if (code.length !== 6) return null;
    for (const c of code) if (!ALPHABET.includes(c)) return null;
    return code;
  }
  const pretty = (code) => code.slice(0, 3) + "-" + code.slice(3);
  const DEVICE = (() => {
    if (navigator.userAgentData && typeof navigator.userAgentData.mobile === "boolean" && navigator.userAgentData.mobile) return "phone";
    const ua = navigator.userAgent || "";
    if (/Android|iPhone|iPad|iPod|Mobile|Silk|Kindle|Opera Mini|IEMobile/i.test(ua)) return "phone";
    // iPadOS pretends to be desktop Safari.
    if (/Macintosh/.test(ua) && navigator.maxTouchPoints > 1) return "phone";
    return "web";
  })();

  async function api(path, params) {
    const qs = new URLSearchParams({ rid: String(rid++), ...params });
    const res = await fetch(path + "?" + qs.toString(), { cache: "no-store" });
    let body = null;
    try { body = await res.json(); } catch {}
    return body || { ok: false, error: "The server did not answer." };
  }

  function show(view) {
    $("join").hidden = view !== "join";
    $("room").hidden = view !== "room";
  }

  async function join() {
    const code = normalize($("code").value);
    const name = $("name").value.trim();
    $("joinErr").textContent = "";
    if (!code) { $("joinErr").textContent = t("badCode"); return; }
    $("joinBtn").disabled = true;
    try {
      const r = await api("/v1/join", { code, name, kind: DEVICE });
      if (!r.ok) { $("joinErr").textContent = friendly(r.error); return; }
      session = { code, token: r.token };
      store.set("crowdtale.session", JSON.stringify(session));
      store.set("crowdtale.name", name, true);
      morph(() => enterRoom(r), $("joinBtn"), "in");
    } catch {
      $("joinErr").textContent = t("noConn");
    } finally {
      $("joinBtn").disabled = false;
    }
  }

  function friendly(error) {
    if (error === "session not found") return t("notFound");
    if (error === "session is full") return t("full");
    if (error && error.startsWith("too many")) return t("tooMany");
    return t("joinFailed");
  }


  const THEMES = { wolf: { cls: "theme-wolf", legal: ["wolfLegal1", "wolfLegal2"] } };
  let theme = null;
  function applyTheme(game) {
    const next = game && THEMES[game] ? game : null;
    if (next === theme) return;
    if (theme) document.body.classList.remove(THEMES[theme].cls);
    theme = next;
    if (theme) document.body.classList.add(THEMES[theme].cls);
    const keys = theme ? THEMES[theme].legal : ["legal1", "legal2"];
    $("legal1").dataset.i18nHtml = keys[0]; $("legal2").dataset.i18nHtml = keys[1];
    $("legal1").innerHTML = t(keys[0]); $("legal2").innerHTML = t(keys[1]);
    $("gameHead").setAttribute("aria-hidden", String(!theme));
  }
  // origin: element the circle grows from (null = screen centre).
  function morph(update, origin, dir) {
    const root = document.documentElement;
    if (!document.startViewTransition || matchMedia("(prefers-reduced-motion: reduce)").matches) { update(); return; }
    let x = innerWidth / 2, y = innerHeight / 2;
    const r = origin && origin.getBoundingClientRect();
    if (r && r.width) { x = r.left + r.width / 2; y = r.top + r.height / 2; }
    const R = Math.hypot(Math.max(x, innerWidth - x), Math.max(y, innerHeight - y)) + 40;
    const ring = document.createElement("div");
    ring.className = "vt-ring";
    Object.assign(ring.style, { left: x - R + "px", top: y - R + "px", width: 2 * R + "px", height: 2 * R + "px", transform: "scale(0)" });
    root.classList.add("vt", dir === "out" ? "vt-out" : "vt-in");
    let vt;
    try { vt = document.startViewTransition(() => { update(); document.body.appendChild(ring); }); }
    catch { root.classList.remove("vt", "vt-in", "vt-out"); update(); return; }
    const timing = { duration: 1100, easing: "cubic-bezier(.65,0,.25,1)", fill: "both" };
    vt.ready.then(() => {
      const small = "circle(0px at " + x + "px " + y + "px)", big = "circle(" + R + "px at " + x + "px " + y + "px)";
      const out = dir === "out";
      root.animate({ clipPath: out ? [big, small] : [small, big] },
        { ...timing, pseudoElement: out ? "::view-transition-old(root)" : "::view-transition-new(root)" });
      ring.animate({ transform: out ? ["scale(1)", "scale(0)"] : ["scale(0)", "scale(1)"], opacity: [1, 1, 0] }, timing);
    }).catch(() => {});
    vt.finished.finally(() => { ring.remove(); root.classList.remove("vt", "vt-in", "vt-out"); });
  }

  function enterRoom(state) {
    applyTheme(state.game || "wolf");
    $("roomCode").textContent = pretty(session.code);
    knownPlayers = null;
    lastSeq = 0;
    if (state.poll && state.poll.result !== null) {
      lastResultSeq = state.poll.seq;
      resultShownAt = 0;
    }
    show("room");
    render(state);
    schedule(400);
  }

  function leave(message, silent, origin) {
    clearTimeout(timer);
    if (session && !message && !silent) api("/v1/leave", { code: session.code, token: session.token }).catch(() => {});
    session = null;
    if (theme && !silent) { morph(() => leftRoom(message), origin || null, "out"); return; }
    leftRoom(message);
  }
  function leftRoom(message) {
    applyTheme(null);
    store.del("crowdtale.session");
    $("code").value = "";
    if (location.search) history.replaceState(null, "", location.pathname);
    show("join");
    $("joinErr").textContent = message || "";
  }

  function schedule(ms) {
    clearTimeout(timer);
    timer = setTimeout(tick, ms);
  }

  async function tick() {
    if (!session) return;
    let open = false;
    const gen = voteGen;
    try {
      const s = await api("/v1/state", { code: session.code, token: session.token });
      if (gen !== voteGen) return;
      if (!s.ok) {
        if (s.error === "removed by the host") { leave(t("removed")); return; }
        if (s.error === "session not found" || s.error === "not a member of this session") {
          leave(t("ended"));
          return;
        }
      } else {
        render(s);
        open = s.poll && s.poll.result === null;
      }
    } catch {}
    schedule(open ? 1000 : 2500);
  }

  function renderPlayers(state) {
    const list = $("players");
    list.textContent = "";
    const voted = new Set(state.poll && state.poll.result === null ? state.poll.voters.map((v) => v.name) : []);
    const current = new Map();
    for (const p of state.names || []) {
      current.set(p.id, p.name);
      const li = document.createElement("li");
      if (voted.has(p.name)) { li.className = "voted"; li.dataset.voted = t("votedTag"); }
      li.append(p.name);
      const tags = [];
      if (p.host) tags.push(t("host"));
      else if (p.kind === "phone") tags.push(t("phone"));
      else if (p.kind === "web") tags.push(t("pc"));
      if (p.id === state.id) tags.push(t("you"));
      if (tags.length) { const t = document.createElement("span"); t.className = "tag"; t.textContent = "(" + tags.join(", ") + ")"; li.append(t); }
      list.appendChild(li);
    }
    if (knownPlayers) {
      for (const [id, name] of current) if (!knownPlayers.has(id)) toast(t("joined", { name }));
      for (const [id, name] of knownPlayers) if (!current.has(id)) toast(t("left", { name }));
    }
    knownPlayers = current;
  }

  function render(state, relabel) {
    lastState = state;
    renderPlayers(state);
    const poll = state.poll;
    const fresh = poll && poll.seq > (state.applied || 0);
    const where = state.hostWhere;
    const idle = { menu: "hostMenu", paused: "hostPaused", away: "hostAway" }[where];
    $("idleTitle").textContent = t(idle ? idle + "Title" : "waitTitle");
    $("idleText").innerHTML = t(idle ? idle + "Text" : "waitText");
    if (where === "away" || !poll || !fresh || (poll.result !== null && poll.seq === lastResultSeq && Date.now() - resultShownAt > 6000)) {
      $("idle").hidden = false;
      $("vote").hidden = true;
      return;
    }
    $("idle").hidden = true;
    $("vote").hidden = false;
    if (relabel) lastSeq = -1;
    if (poll.seq !== lastSeq) {
      const firstDraw = lastSeq !== -1;
      lastSeq = poll.seq;
      knownVoters = 0;
      timerStart = poll.remaining || null;
      buildChoices(poll);
      if (firstDraw && poll.result === null && navigator.vibrate) navigator.vibrate(60);
    }
    updateChoices(poll, state);
  }

  function buildChoices(poll) {
    const box = $("choices");
    box.textContent = "";
    poll.texts.forEach((text, i) => {
      if (!text) return;
      const b = document.createElement("button");
      b.className = "choice";
      b.style.setProperty("--c", "var(--c" + (i % 8) + ")");
      b.dataset.index = String(i);
      const key = document.createElement("span"); key.className = "key";
      const num = document.createElement("b"); num.textContent = String(i + 1); key.append(num);
      const txt = document.createElement("span"); txt.className = "txt"; txt.textContent = text;
      const pct = document.createElement("span"); pct.className = "pct";
      const fill = document.createElement("span"); fill.className = "fill";
      b.append(key, txt, pct, fill);
      b.addEventListener("click", () => vote(poll.seq, i));
      box.appendChild(b);
    });
  }

  function updateChoices(poll, state) {
    const total = poll.votes.reduce((a, b) => a + b, 0);
    const closed = poll.result !== null;
    $("voteTitle").textContent = t(closed ? "decided" : poll.paused ? "paused" : "makeChoice");
    $("voteCount").textContent = t("voted", { n: total, total: state.players });
    for (const b of $("choices").children) {
      const i = Number(b.dataset.index);
      const n = poll.votes[i] || 0;
      const share = total ? Math.round((n / total) * 100) : 0;
      b.querySelector(".fill").style.width = share + "%";
      b.querySelector(".pct").textContent = total ? share + "%" : "";
      b.classList.toggle("mine", poll.mine === i);
      b.classList.toggle("win", closed && poll.result === i);
      b.classList.toggle("lose", closed && poll.result !== i);
      b.disabled = closed;
    }
    if (!closed && poll.voters.length > knownVoters) {
      for (const v of poll.voters.slice(knownVoters)) if (v.name !== myName()) toast(t("votedToast", { name: v.name }));
      knownVoters = poll.voters.length;
    }
    const bar = $("timerBar");
    if (!closed && typeof poll.remaining === "number" && timerStart) {
      bar.hidden = false;
      $("timerFill").style.width = Math.max(0, (poll.remaining / timerStart) * 100) + "%";
    } else {
      bar.hidden = true;
    }
    const status = $("voteStatus");
    if (closed) {
      status.className = "status done";
      status.textContent = poll.texts[poll.result] || "Option " + (poll.result + 1);
      if (lastResultSeq !== poll.seq) {
        lastResultSeq = poll.seq;
        resultShownAt = Date.now();
        toast(t("decided"));
        if (navigator.vibrate) navigator.vibrate([40, 60, 40]);
      }
    } else if (poll.paused) {
      status.className = "status";
      status.textContent = t("pausedNote");
    } else if (poll.mine !== undefined) {
      status.className = "status good";
      status.textContent = t("sent");
    } else {
      status.className = "status";
      status.textContent = t("tap");
    }
  }

  function myName() { return ($("name").value || "").trim(); }

  async function vote(seq, index) {
    if (!session) return;
    const gen = ++voteGen;
    clearTimeout(timer);
    // Optimistic update; the reply below has the real counts.
    const poll = lastState && lastState.poll;
    if (poll && poll.seq === seq && poll.result === null && poll.mine !== index) {
      if (poll.mine !== undefined && poll.votes[poll.mine] > 0) poll.votes[poll.mine]--;
      poll.votes[index] = (poll.votes[index] || 0) + 1;
      poll.mine = index;
      updateChoices(poll, lastState);
    }
    $("voteStatus").className = "status good";
    $("voteStatus").textContent = t("sending");
    try {
      const r = await api("/v1/vote", { code: session.code, token: session.token, seq: String(seq), index: String(index), view: "1" });
      if (gen !== voteGen) return;
      if (!r.ok) { $("voteStatus").className = "status"; $("voteStatus").textContent = t("closed"); }
      else if (r.code) render(r);
    } catch {
      if (gen !== voteGen) return;
      $("voteStatus").className = "status";
      $("voteStatus").textContent = t("noConnTap");
    }
    schedule(1000);
  }

  $("joinBtn").addEventListener("click", join);
  $("leaveBtn").addEventListener("click", () => leave("", false, $("leaveBtn")));
  $("code").addEventListener("input", (e) => {
    const raw = e.target.value.toUpperCase().replace(/[^0-9A-Z]/g, "").slice(0, 6);
    e.target.value = raw.length > 3 ? raw.slice(0, 3) + "-" + raw.slice(3) : raw;
  });
  for (const id of ["code", "name"]) $(id).addEventListener("keydown", (e) => { if (e.key === "Enter") join(); });

  const deviceLang = (navigator.languages || [navigator.language || "en"]).map((l) => String(l).slice(0, 2).toLowerCase())
    .find((l) => LANGUAGES.includes(l));
  applyLanguage(store.get("crowdtale.lang") || deviceLang || "en");

  const params = new URLSearchParams(location.search);
  if (params.get("code")) { $("code").value = params.get("code"); $("code").dispatchEvent(new Event("input")); }
  $("name").value = store.get("crowdtale.name") || "";
  try {
    const saved = JSON.parse(store.get("crowdtale.session") || "null");
    const linkCode = normalize(params.get("code"));
    // A ?code= link to another session wins over the saved one.
    if (saved && linkCode && saved.code !== linkCode) {
      api("/v1/leave", { code: saved.code, token: saved.token }).catch(() => {});
      store.del("crowdtale.session");
    } else if (saved && normalize(saved.code) && /^[0-9a-f]{32}$/.test(saved.token)) {
      session = saved;
      api("/v1/state", { code: saved.code, token: saved.token }).then((s) => {
        if (s.ok) enterRoom(s); else leave("", true);
      }).catch(() => leave("", true));
    }
  } catch {}
})();
</script>
</body>
</html>`
  .replaceAll("\${DAMASK}", DAMASK)
  .replaceAll("\${DIVIDER}", DIVIDER)
  .replace("/*FONT_FACES*/", () => FONT_FACES)
  .replace("/*TEXTS*/", () => JSON.stringify(TEXTS).replace(/</g, "\\u003c"))
  .replace("/*LANGUAGES*/", () => JSON.stringify(LANGUAGES));
