// Türkçe on GitHub Pages: saves each person's settings and progress to Supabase.
// It provides the same small database API the page used inside Claude artifacts
// (window.claude.use("db" | "user")), backed by the public.user_docs table
// (see supabase_setup.sql), and adds sign-in / sign-out to the header.
(function(){
  var SUPABASE_URL = "https://ktlnputpwbpwsvsuqnie.supabase.co";
  var SUPABASE_KEY = "sb_publishable_xTvijQLingPhZnygIl3dnA_2KOrV3_i";
  var client = window.supabase.createClient(SUPABASE_URL, SUPABASE_KEY);
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
.account-menu{position:absolute;top:calc(100% + 6px);right:0;z-index:20;width:250px;max-width:calc(100vw - 32px);padding:12px;border:1px solid var(--line);border-radius:12px;background:#fff;box-shadow:var(--shadow);}
.account-email{margin:0 0 8px;padding-bottom:8px;border-bottom:1px solid var(--line);font-size:13px;font-weight:600;color:var(--ink);overflow-wrap:anywhere;}
.account-menu p{margin:0 0 10px;font-size:12.5px;line-height:1.45;color:var(--ink-soft);}
.account-menu .btn{width:100%;padding:9px 14px;font-size:0.85rem;}
@media (max-width:560px){.account-menu{right:auto;left:0;}}
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
    var emailEl = menu.querySelector("#accountEmail");
    emailEl.textContent = signedInEmail || "";
    emailEl.hidden = !signedInEmail;
    document.getElementById("syncStatus").setAttribute("aria-expanded", open ? "true" : "false");
    if(open) menu.querySelector("button").focus();
  }
  document.addEventListener("click", function(ev){
    if(menu && !menu.hidden && !ev.target.closest(".account-wrap")) toggleMenu(false);
  });

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
    // Wrap the pill so the dropdown can hang from it.
    var wrap = document.createElement("div");
    wrap.className = "account-wrap";
    pill.parentNode.insertBefore(wrap, pill);
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
      var saved = JSON.parse(localStorage.getItem("sb-ktlnputpwbpwsvsuqnie-auth-token") || "null");
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

  if(document.readyState === "loading") document.addEventListener("DOMContentLoaded", setup);
  else setup();
})();
