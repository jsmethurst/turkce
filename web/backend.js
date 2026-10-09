// Türkçe on GitHub Pages: saves each person's settings and progress to Supabase.
// It provides the same small database API the page used inside Claude artifacts
// (window.claude.use("db" | "user")), backed by the public.user_docs table
// (see supabase_setup.sql), and adds sign-in / sign-out to the header.
(function(){
  var SUPABASE_URL = "https://ktlnputpwbpwsvsuqnie.supabase.co";
  var SUPABASE_KEY = "sb_publishable_xTvijQLingPhZnygIl3dnA_2KOrV3_i";
  // On localhost, web/testmode.js provides a pretend Supabase with a signed-in Test learner.
  var TEST = window.turkceTestMode || null;
  var client = TEST ? TEST.client : window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
  var CLIENT_ID = Math.random().toString(36).slice(2) + Date.now().toString(36);
  var sessionReady = client.auth.getSession().then(function(r){ return r.data.session; });

  // ---------- database: documents keyed by name, one row each ----------
  function dbError(error){
    var e = new Error(error && error.message || "Database error");
    var msg = String(error && error.message || "");
    e.code = (!navigator.onLine || /fetch|network|timeout/i.test(msg)) ? "unavailable" : (error && error.code) || "failed";
    return e;
  }
  function snapshot(id, row){
    var data = row ? row.data : undefined;
    return {
      id: id, exists: !!row,
      data: function(){ return data === undefined ? undefined : JSON.parse(JSON.stringify(data)); },
      metadata: {hasPendingWrites:false, fromCache:false}
    };
  }
  function docName(path){
    // "data/users/<uid>/settings" -> "settings"; ".../tests/lists/<key>" -> "tests/lists/<key>"
    return path.split("/").slice(3).join("/");
  }
  async function uid(){ var s = await sessionReady; return s ? s.user.id : null; }

  async function readDoc(name){
    var r = await client.from("user_docs").select("data").eq("doc", name).maybeSingle();
    if(r.error) throw dbError(r.error);
    return r.data;
  }
  var listeners = {}, channel = null;
  async function listen(name, cb){
    (listeners[name] = listeners[name] || []).push(cb);
    if(channel) return;
    var id = await uid();
    channel = client.channel("user_docs:" + id)
      .on("postgres_changes", {event:"*", schema:"public", table:"user_docs", filter:"user_id=eq." + id}, async function(p){
        var row = p.new && p.new.doc ? p.new : null;
        if(!row || row.writer === CLIENT_ID || !listeners[row.doc]) return;
        try{
          var fresh = await readDoc(row.doc);   // fetch rather than trust the event payload (large rows may be cut)
          listeners[row.doc].forEach(function(f){ f(snapshot(row.doc, fresh)); });
        }catch(e){}
      })
      .subscribe();
  }
  function docRef(name){
    return {
      id: name.split("/").pop(),
      get: async function(){ return snapshot(name, await readDoc(name)); },
      set: async function(data){
        var r = await client.from("user_docs").upsert(
          {user_id: await uid(), doc: name, data: data, writer: CLIENT_ID, updated_at: new Date().toISOString()},
          {onConflict: "user_id,doc"});
        if(r.error) throw dbError(r.error);
      },
      update: async function(patch){
        var r = await client.rpc("merge_doc", {p_doc: name, p_patch: patch, p_writer: CLIENT_ID});
        if(r.error) throw dbError(r.error);
      },
      onSnapshot: function(cb){ listen(name, cb); return function(){}; }
    };
  }
  function collectionRef(prefix){
    return {
      doc: function(key){ return docRef(prefix + "/" + key); },
      get: async function(){
        var r = await client.from("user_docs").select("doc,data").like("doc", prefix + "/%");
        if(r.error) throw dbError(r.error);
        var docs = (r.data || []).map(function(row){ return snapshot(row.doc.slice(prefix.length + 1), row); });
        return {empty: !docs.length, docs: docs};
      },
      // The word list is built into the page here, so dictionary queries return nothing.
      orderBy: function(){ return this; }, limit: function(){ return this; }
    };
  }
  var db = {
    doc: function(path){
      var name = docName(path);
      var ref = docRef(name);
      ref.collection = function(sub){ return collectionRef(name + "/" + sub); };
      return ref;
    },
    collection: function(){ return {orderBy: function(){ return this; }, limit: function(){ return this; },
      get: async function(){ return {empty:true, docs:[]}; }}; }
  };
  var user = {id: uid};
  window.claude = {use: async function(name){ return name === "db" ? db : name === "user" ? user : null; }};

  // ---------- sign in / sign out ----------
  var css = `
header{flex-wrap:wrap;}
.sync-status.clickable{display:block;cursor:pointer;font:inherit;font-size:12px;background:transparent;min-width:0;max-width:100%;overflow:hidden;text-overflow:ellipsis;}
.sync-status.clickable::before{display:inline-block;margin-right:6px;vertical-align:1px;}
.account-wrap{position:relative;min-width:0;max-width:100%;}
.update-bar{position:fixed;left:50%;bottom:calc(16px + env(safe-area-inset-bottom, 0px));transform:translateX(-50%);z-index:50;display:flex;align-items:center;gap:12px;max-width:calc(100vw - 32px);padding:10px 10px 10px 16px;border-radius:12px;background:var(--tile-blue-deep);color:#fff;font-size:14px;box-shadow:0 8px 24px -8px rgba(18,65,77,.5);}
.update-bar .btn{padding:8px 14px;font-size:0.85rem;background:#fff;color:var(--tile-blue-deep);}
.update-bar .btn:hover{background:var(--paper);}
.update-close{background:none;border:none;color:#fff;opacity:.7;font-size:20px;line-height:1;padding:2px 6px;cursor:pointer;}
.update-close:hover{opacity:1;}
.testmode-badge{margin-top:6px;padding:5px 10px;border-radius:999px;background:#FBE3CF;color:#8A3D0E;font-size:11.5px;font-weight:700;white-space:nowrap;}
.header-actions{display:flex;align-items:flex-start;gap:8px;min-width:0;max-width:100%;}
.feedback-wrap{position:relative;flex:none;}
.feedback-btn{display:flex;align-items:center;justify-content:center;width:28px;height:28px;margin-top:6px;padding:0;border:1px solid var(--line);border-radius:50%;background:transparent;color:var(--ink-soft);cursor:pointer;}
.feedback-btn:hover,.feedback-btn[aria-expanded="true"]{background:var(--paper-2);color:var(--ink);}
.feedback-btn:focus-visible{outline:2px solid var(--tile-turquoise);outline-offset:2px;}
.feedback-btn svg{width:15px;height:15px;}
.feedback-pop{position:absolute;top:calc(100% + 6px);right:0;z-index:20;width:300px;max-width:calc(100vw - 32px);padding:14px;border:1px solid var(--line);border-radius:12px;background:#fff;box-shadow:var(--shadow);}
.feedback-title{font-family:'Fraunces',serif;font-weight:600;font-size:1rem;color:var(--ink);margin-bottom:10px;}
.feedback-kinds{display:flex;gap:6px;margin-bottom:10px;}
.feedback-kind{font:inherit;font-size:12.5px;font-weight:600;padding:5px 12px;border-radius:999px;border:1.5px solid var(--line);background:transparent;color:var(--ink-soft);cursor:pointer;}
.feedback-kind.on{background:var(--tile-blue-deep);border-color:var(--tile-blue-deep);color:#fff;}
.feedback-label{display:block;font-size:12px;font-weight:600;color:var(--ink-soft);margin-bottom:4px;}
#feedbackText{width:100%;box-sizing:border-box;font:inherit;font-size:14px;line-height:1.45;padding:9px 10px;border-radius:10px;border:1.5px solid var(--line);background:var(--paper);color:var(--ink);resize:vertical;outline:none;}
#feedbackText:focus{border-color:var(--tile-turquoise);background:#fff;}
.feedback-note{margin:8px 0 10px;font-size:11.5px;line-height:1.45;color:var(--ink-soft);}
.feedback-pop .btn{width:100%;padding:9px 14px;font-size:0.85rem;}
.feedback-msg{margin:8px 0 0;font-size:12.5px;}
.feedback-msg.good{color:var(--good);}
.feedback-msg.bad{color:var(--bad);}

.account-menu{position:absolute;top:calc(100% + 6px);right:0;z-index:20;width:250px;max-width:calc(100vw - 32px);padding:12px;border:1px solid var(--line);border-radius:12px;background:#fff;box-shadow:var(--shadow);}
.account-email{margin:0 0 8px;padding-bottom:8px;border-bottom:1px solid var(--line);font-size:13px;font-weight:600;color:var(--ink);overflow-wrap:anywhere;}
.account-menu p{margin:0 0 10px;font-size:12.5px;line-height:1.45;color:var(--ink-soft);}
.account-menu .btn{width:100%;padding:9px 14px;font-size:0.85rem;}
.sync-status.clickable:hover{background:var(--paper-2);}
.sync-status.clickable:focus-visible{outline:2px solid var(--tile-turquoise);outline-offset:2px;}
.auth-panel{margin:-8px 0 22px;padding:18px;border:1px solid var(--line);border-radius:var(--radius);background:#fff;box-shadow:var(--shadow);}
.auth-panel h2{font-family:'Fraunces',serif;font-weight:600;font-size:1.15rem;margin:0 0 4px;color:var(--ink);}
.auth-panel p{margin:0 0 14px;font-size:13px;line-height:1.5;color:var(--ink-soft);}
.auth-fields{display:grid;gap:10px;margin-bottom:12px;}
.auth-fields label{display:grid;gap:4px;font-size:12px;font-weight:600;color:var(--ink-soft);}
.auth-fields input{font:inherit;font-size:15px;padding:11px 12px;border-radius:10px;border:1.5px solid var(--line);background:var(--paper);color:var(--ink);outline:none;}
.auth-fields input:focus{border-color:var(--tile-turquoise);background:#fff;}
.auth-actions{display:flex;flex-wrap:wrap;gap:8px;align-items:center;}
.auth-actions .btn{padding:10px 16px;}
.auth-link{background:none;border:none;padding:4px 2px;font:inherit;font-size:13px;color:var(--tile-blue);text-decoration:underline;cursor:pointer;margin-left:auto;}
.auth-msg{margin:12px 0 0;font-size:13px;line-height:1.5;}
.auth-msg.bad{color:var(--bad);}
.auth-msg.good{color:var(--good);}
`;
  var panel, mode = "signin", recovering = false;

  function el(html){ var d = document.createElement("div"); d.innerHTML = html.trim(); return d.firstChild; }
  function esc(s){ return String(s).replace(/[&<>"]/g, function(c){ return {"&":"&amp;","<":"&lt;",">":"&gt;",'"':"&quot;"}[c]; }); }
  function msg(text, kind){
    var m = panel.querySelector(".auth-msg");
    m.textContent = text || ""; m.className = "auth-msg" + (kind ? " " + kind : ""); m.hidden = !text;
  }
  function busy(on){ panel.querySelectorAll("button,input").forEach(function(b){ b.disabled = on; }); }

  async function render(){
    var session = await sessionReady;
    if(recovering){
      panel.innerHTML = `
        <h2>Choose a new password</h2>
        <p>Type a new password for your account.</p>
        <div class="auth-fields"><label for="authNewPassword">New password
          <input id="authNewPassword" type="password" autocomplete="new-password" minlength="6"></label></div>
        <div class="auth-actions"><button class="btn btn-primary" id="authSavePassword">Save password</button></div>
        <p class="auth-msg" hidden></p>`;
      panel.querySelector("#authSavePassword").onclick = async function(){
        var pw = panel.querySelector("#authNewPassword").value;
        if(pw.length < 6) return msg("Use at least 6 characters.", "bad");
        busy(true);
        var r = await client.auth.updateUser({password: pw});
        busy(false);
        if(r.error) return msg(r.error.message, "bad");
        recovering = false;
        location.reload();
      };
      return;
    }
    var creating = mode === "signup";
    panel.innerHTML = `
      <h2>${creating ? "Create an account" : "Sign in"}</h2>
      <p>${creating ? "Make an account to save your settings and progress and keep them in sync across your devices."
                    : "Sign in to save your settings and progress and keep them in sync across your devices. Until then, they're saved in this browser only."}</p>
      <div class="auth-fields">
        <label for="authEmail">Email<input id="authEmail" type="email" autocomplete="email" inputmode="email"></label>
        <label for="authPassword">Password<input id="authPassword" type="password" autocomplete="${creating ? "new-password" : "current-password"}"></label>
      </div>
      <div class="auth-actions">
        <button class="btn btn-primary" id="authSubmit">${creating ? "Create account" : "Sign in"}</button>
        <button class="btn btn-ghost" id="authSwitch">${creating ? "I have an account" : "Create an account"}</button>
        ${creating ? "" : '<button class="auth-link" id="authForgot">Forgot password?</button>'}
      </div>
      <p class="auth-msg" hidden></p>`;
    var email = panel.querySelector("#authEmail"), pw = panel.querySelector("#authPassword");
    async function submit(){
      var e = email.value.trim(), p = pw.value;
      if(!e || !p) return msg("Enter your email and a password.", "bad");
      if(creating && p.length < 6) return msg("Use a password of at least 6 characters.", "bad");
      busy(true);
      var r = creating ? await client.auth.signUp({email: e, password: p})
                       : await client.auth.signInWithPassword({email: e, password: p});
      busy(false);
      if(r.error) return msg(r.error.message === "Invalid login credentials" ? "That email and password don't match an account." : r.error.message, "bad");
      if(creating && !r.data.session) return msg("Check your email for a link to confirm your account, then sign in here.", "good");
      location.reload();
    }
    panel.querySelector("#authSubmit").onclick = submit;
    [email, pw].forEach(function(i){ i.addEventListener("keydown", function(ev){ if(ev.key === "Enter"){ ev.preventDefault(); ev.stopPropagation(); submit(); } }); });
    panel.querySelector("#authSwitch").onclick = function(){ mode = creating ? "signin" : "signup"; render().then(function(){ panel.querySelector("#authEmail").focus(); }); };
    var forgot = panel.querySelector("#authForgot");
    if(forgot) forgot.onclick = async function(){
      var e = email.value.trim();
      if(!e) return msg("Type your email above first, then press Forgot password.", "bad");
      busy(true);
      var r = await client.auth.resetPasswordForEmail(e, {redirectTo: location.origin + location.pathname});
      busy(false);
      if(r.error) return msg(r.error.message, "bad");
      msg("If that email has an account, a link to reset the password is on its way.", "good");
    };
  }

  // Signed in: a small dropdown under the status pill with Sign out.
  var menu;
  function buildMenu(){
    menu = el(`<div class="account-menu" id="accountMenu" role="menu" hidden>
      <div class="account-email" id="accountEmail"></div>
      <p>Your settings and progress are saved to your account and stay in sync on every device you sign in on.</p>
      <button class="btn btn-ghost" id="authSignOut" role="menuitem" type="button">Sign out</button>
    </div>`);
    menu.querySelector("#authSignOut").onclick = async function(){
      this.disabled = true;
      await client.auth.signOut();
      // Don't leave this person's progress behind for the next person on this device.
      try{ Object.keys(localStorage).filter(function(k){ return k.indexOf("fiil_") === 0; }).forEach(function(k){ localStorage.removeItem(k); }); }catch(e){}
      location.reload();
    };
    menu.addEventListener("keydown", function(ev){ ev.stopPropagation(); if(ev.key === "Escape") toggleMenu(false); });
    return menu;
  }
  function toggleMenu(force){
    var open = typeof force === "boolean" ? force : menu.hidden;
    menu.hidden = !open;
    if(open) placePopover(menu);
    var emailEl = menu.querySelector("#accountEmail");
    emailEl.textContent = signedInEmail || "";
    emailEl.hidden = !signedInEmail;
    document.getElementById("syncStatus").setAttribute("aria-expanded", open ? "true" : "false");
    if(open) menu.querySelector("button").focus();
  }
  document.addEventListener("click", function(ev){
    if(menu && !menu.hidden && !ev.target.closest(".account-wrap")) toggleMenu(false);
    if(fb && !fb.pop.hidden && !ev.target.closest(".feedback-wrap")) toggleFeedback(false);
  });

  // Keep a popover on screen: line its right edge up with its button's, then
  // nudge it so it stays at least 16px from both sides of the window.
  function placePopover(pop){
    var anchor = pop.parentNode.getBoundingClientRect();
    var vw = document.documentElement.clientWidth;
    pop.style.left = "0px"; pop.style.right = "auto";
    var w = pop.getBoundingClientRect().width;
    var left = Math.min(Math.max(anchor.right - w, 16), vw - 16 - w);
    pop.style.left = (left - anchor.left) + "px";
  }
  window.addEventListener("resize", function(){
    if(menu && !menu.hidden) placePopover(menu);
    if(fb && !fb.pop.hidden) placePopover(fb.pop);
  });

  // ---------- bug reports & feedback ----------
  // Rows go to public.feedback (insert-only for the public); the "Sync feedback"
  // workflow turns them into GitHub Issues for Jacob to work through.
  var BUG_ICON = '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><path d="m8 2 1.88 1.88"/><path d="M14.12 3.88 16 2"/><path d="M9 7.13v-1a3 3 0 1 1 6 0v1"/><path d="M12 20c-3.3 0-6-2.7-6-6v-3a4 4 0 0 1 4-4h4a4 4 0 0 1 4 4v3c0 3.3-2.7 6-6 6"/><path d="M12 20v-9"/><path d="M6.53 9C4.6 8.8 3 7.1 3 5"/><path d="M6 13H2"/><path d="M3 21c0-2.1 1.7-3.9 3.8-4"/><path d="M20.97 5c0 2.1-1.6 3.8-3.5 4"/><path d="M22 13h-4"/><path d="M17.2 17c2.1.1 3.8 1.9 3.8 4"/></svg>';
  var fb = null;
  function screenContext(){
    var tab = document.querySelector(".tab.active");
    var name = tab ? tab.textContent.trim() : "?";
    var shown = "";
    var id = tab && tab.dataset.tab === "verbs" ? "promptWord" : tab && tab.dataset.tab === "vocab" ? "vocabFront" : "";
    if(id){ var e = document.getElementById(id); if(e) shown = e.textContent.trim(); }
    return (name + (shown ? ' — "' + shown + '"' : "")).slice(0, 1000);
  }
  function buildFeedback(){
    var w = el(`<div class="feedback-wrap">
      <button class="feedback-btn" id="feedbackBtn" type="button" title="Report a bug or send feedback" aria-label="Report a bug or send feedback" aria-haspopup="true" aria-expanded="false">${BUG_ICON}</button>
      <div class="feedback-pop" id="feedbackPop" role="dialog" aria-label="Send feedback" hidden>
        <div class="feedback-title">Report a bug or suggest something</div>
        <div class="feedback-kinds" role="radiogroup" aria-label="Type">
          <button type="button" class="feedback-kind on" data-kind="bug" role="radio" aria-checked="true">Bug</button>
          <button type="button" class="feedback-kind" data-kind="idea" role="radio" aria-checked="false">Idea</button>
        </div>
        <label class="feedback-label" for="feedbackText">What happened, or what would you like?</label>
        <textarea id="feedbackText" rows="4" maxlength="4000"></textarea>
        <p class="feedback-note">This goes to Jacob's to-do list on GitHub, which is public. Your name and email aren't included.</p>
        <button class="btn btn-primary" id="feedbackSend" type="button">Send</button>
        <p class="feedback-msg" id="feedbackMsg" role="status" hidden></p>
      </div>
    </div>`);
    fb = {wrap: w, btn: w.querySelector("#feedbackBtn"), pop: w.querySelector("#feedbackPop"),
          text: w.querySelector("#feedbackText"), send: w.querySelector("#feedbackSend"), msg: w.querySelector("#feedbackMsg"), kind: "bug"};
    fb.btn.onclick = function(){ if(menu) toggleMenu(false); toggleFeedback(); };
    w.querySelectorAll(".feedback-kind").forEach(function(k){
      k.onclick = function(){
        fb.kind = k.dataset.kind;
        w.querySelectorAll(".feedback-kind").forEach(function(x){ var on = x === k; x.classList.toggle("on", on); x.setAttribute("aria-checked", on ? "true" : "false"); });
      };
    });
    fb.pop.addEventListener("keydown", function(ev){ ev.stopPropagation(); if(ev.key === "Escape"){ toggleFeedback(false); fb.btn.focus(); } });
    fb.send.onclick = async function(){
      var message = fb.text.value.trim();
      if(!message){ return showFb("Type a message first.", "bad"); }
      fb.send.disabled = true;
      showFb("Sending…");
      var r = await client.from("feedback").insert({
        kind: fb.kind, message: message, context: screenContext(), user_agent: navigator.userAgent.slice(0, 400)
      });
      fb.send.disabled = false;
      if(r.error) return showFb("Couldn't send it. Check your connection and try again.", "bad");
      fb.text.value = "";
      showFb("Thanks! Sent to Jacob.", "good");
      setTimeout(function(){ toggleFeedback(false); }, 1600);
    };
    return w;
  }
  function showFb(text, kind){ fb.msg.textContent = text; fb.msg.className = "feedback-msg" + (kind ? " " + kind : ""); fb.msg.hidden = !text; }
  function toggleFeedback(force){
    var open = typeof force === "boolean" ? force : fb.pop.hidden;
    fb.pop.hidden = !open;
    if(open) placePopover(fb.pop);
    fb.btn.setAttribute("aria-expanded", open ? "true" : "false");
    if(open){ showFb(""); fb.text.focus(); }
  }

  function togglePanel(force){
    var open = typeof force === "boolean" ? force : panel.hidden;
    panel.hidden = !open;
    if(open) render().then(function(){ var f = panel.querySelector("input"); if(f) f.focus(); });
  }

  function setup(){
    var style = document.createElement("style"); style.textContent = css; document.head.appendChild(style);
    var note = document.getElementById("syncNote");
    panel = el('<section class="auth-panel" id="authPanel" aria-label="Account" hidden></section>');
    note.parentNode.insertBefore(panel, note.nextSibling);
    // Keep typing in the sign-in form from triggering the drill's keyboard shortcuts.
    panel.addEventListener("keydown", function(ev){ ev.stopPropagation(); });
    // Make the existing status pill clickable rather than swapping in a <button>:
    // Safari didn't repaint a <button>'s new text until it was hovered.
    var pill = document.getElementById("syncStatus");
    pill.classList.add("clickable");
    pill.setAttribute("role", "button");
    pill.tabIndex = 0;
    // Header right side: [bug button] [status pill]. Each wrap anchors its own popover.
    var actions = document.createElement("div");
    actions.className = "header-actions";
    pill.parentNode.insertBefore(actions, pill);
    if(TEST) actions.appendChild(el('<span class="testmode-badge" title="Local test mode: a pretend database in this browser, signed in as a Test learner. Add ?supabase to the address to use the real one.">Local test mode</span>'));
    actions.appendChild(buildFeedback());
    var wrap = document.createElement("div");
    wrap.className = "account-wrap";
    actions.appendChild(wrap);
    wrap.appendChild(pill);
    wrap.appendChild(buildMenu());
    pill.setAttribute("aria-haspopup", "true");
    pill.setAttribute("aria-expanded", "false");
    pill.onclick = function(){ if(signedInEmail !== null && !recovering){ panel.hidden = true; toggleMenu(); } else togglePanel(); };
    pill.addEventListener("keydown", function(ev){
      if(ev.key === "Enter" || ev.key === " "){ ev.preventDefault(); ev.stopPropagation(); pill.onclick(); }
      else if(ev.key === "Escape" && menu && !menu.hidden){ ev.stopPropagation(); toggleMenu(false); }
    });
    // Show the status straight away rather than after all the data has loaded:
    // a saved sign-in in this browser means "signed in" (the page corrects it if saving fails).
    try{
      var saved = TEST ? TEST.session() : JSON.parse(localStorage.getItem("sb-ktlnputpwbpwsvsuqnie-auth-token") || "null");
      if(saved && saved.user) signedInEmail = saved.user.email || "";
    }catch(e){}
    if(signedInEmail !== null && !pill.textContent){ pill.textContent = signedInLabel(); pill.classList.remove("local"); pill.hidden = false; }
    sessionReady.then(function(session){
      if(!session){ signedInEmail = null; window.turkceBackend.signedOut(); return; }
      signedInEmail = session.user.email || "";
      if(!pill.classList.contains("local") || !pill.textContent){ pill.textContent = signedInLabel(); pill.classList.remove("local"); pill.hidden = false; }
    });
  }

  var signedInEmail = null;   // null = not signed in
  function signedInLabel(){ return signedInEmail === null ? "" : "Signed in"; }

  window.turkceBackend = {
    accountName: "your account",
    // The page shows this in the status pill once saving to the account works.
    signedInLabel: signedInLabel,
    // The page calls this when nobody is signed in.
    signedOut: function(){
      var b = document.getElementById("syncStatus");
      b.textContent = "Sign in to sync"; b.classList.add("local"); b.hidden = false;
    }
  };

  client.auth.onAuthStateChange(function(event){
    if(event === "PASSWORD_RECOVERY"){ recovering = true; if(panel) togglePanel(true); }
  });

  // ---------- "new version available" bar ----------
  // Each build has a version (meta app-version + version.json). Pages left open
  // check now and then and offer a reload rather than reloading mid-answer.
  var lastCheck = 0, updateShown = false;
  async function checkForUpdate(){
    var meta = document.querySelector('meta[name="app-version"]');
    if(!meta || updateShown || Date.now() - lastCheck < 15 * 1000) return;
    lastCheck = Date.now();
    try{
      var r = await fetch("version.json", {cache: "no-store"});
      if(!r.ok) return;
      var live = (await r.json()).version;
      if(live && live !== meta.content) showUpdateBar();
    }catch(e){}
  }
  function showUpdateBar(){
    updateShown = true;
    var bar = el(`<div class="update-bar" role="status">
      <span>Türkçe has been updated.</span>
      <button type="button" class="btn btn-primary" id="updateReload">Reload</button>
      <button type="button" class="update-close" aria-label="Dismiss">×</button>
    </div>`);
    bar.querySelector("#updateReload").onclick = function(){ location.reload(); };
    bar.querySelector(".update-close").onclick = function(){ bar.remove(); };
    document.body.appendChild(bar);
  }
  document.addEventListener("visibilitychange", checkForUpdate);
  window.addEventListener("focus", checkForUpdate);
  setInterval(checkForUpdate, 60 * 1000);

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", setup);
  else setup();
})();
