// Test mode: a pretend Supabase that backend.js uses instead of the real one. It is on
// when the site is opened from localhost (e.g. a preview of _site/), or on the live site
// after "Use test mode" in the sign-in panel (until Sign out). A "Test learner" is
// signed in by default and everything is saved in this browser's localStorage, so
// signed-in features (sync, tests, the account menu, feedback) can be tried without a
// real account and without touching real learners' data.
// Otherwise this file does nothing. Add ?supabase to a localhost URL to use the real Supabase.
(function(){
  var FLAG_KEY = "turkce_testmode_on";
  var host = location.hostname;
  var local = host === "localhost" || host === "127.0.0.1" || host === "[::1]" || /\.localhost$/.test(host);
  var chosen = false;
  try{ chosen = localStorage.getItem(FLAG_KEY) === "1"; }catch(e){}
  if(!(local || chosen) || (local && /[?&]supabase\b/.test(location.search))) return;

  var DB_KEY = "turkce_testmode_db", SESSION_KEY = "turkce_testmode_session", FEEDBACK_KEY = "turkce_testmode_feedback";
  var USER = {id: "00000000-0000-4000-8000-000000000001", email: "test.learner@localhost"};

  function read(key, fallback){ try{ var v = localStorage.getItem(key); return v === null ? fallback : JSON.parse(v); }catch(e){ return fallback; } }
  function write(key, value){ try{ localStorage.setItem(key, JSON.stringify(value)); }catch(e){} }
  function clone(x){ return x === undefined ? undefined : JSON.parse(JSON.stringify(x)); }
  // Signed in as the Test learner unless signed out (stored as null).
  function session(){ var s = read(SESSION_KEY, "default"); return s === "default" ? {user: USER} : s; }
  function db(){ return read(DB_KEY, {}); }
  function deepMerge(a, b){
    if(!a || typeof a !== "object" || Array.isArray(a) || !b || typeof b !== "object" || Array.isArray(b)) return clone(b);
    var out = clone(a);
    Object.keys(b).forEach(function(k){ out[k] = deepMerge(a[k], b[k]); });
    return out;
  }
  var denied = {message: "permission denied (not signed in)", code: "42501"};
  var ok = function(data){ return Promise.resolve({data: data === undefined ? null : data, error: null}); };

  function from(table){
    if(table === "feedback"){
      return {insert: function(row){
        var list = read(FEEDBACK_KEY, []);
        list.push(Object.assign({id: list.length + 1, created_at: new Date().toISOString(), email: session() ? session().user.email : null}, clone(row)));
        write(FEEDBACK_KEY, list);
        return ok();
      }};
    }
    return {
      select: function(){
        var filters = [];
        function run(single){
          if(!session()) return Promise.resolve({data: single ? null : [], error: denied});
          var d = db();
          var rows = Object.keys(d).map(function(k){ return {doc: k, data: clone(d[k])}; })
                     .filter(function(r){ return filters.every(function(f){ return f(r); }); });
          return ok(single ? (rows[0] ? {data: rows[0].data} : null) : rows);
        }
        var q = {
          eq: function(col, val){ filters.push(function(r){ return r[col] === val; }); return q; },
          like: function(col, pattern){ var pre = pattern.replace(/%$/, ""); filters.push(function(r){ return String(r[col]).indexOf(pre) === 0; }); return q; },
          maybeSingle: function(){ return run(true); },
          then: function(resolve, reject){ return run(false).then(resolve, reject); }
        };
        return q;
      },
      upsert: function(row){
        if(!session()) return Promise.resolve({error: denied});
        var d = db(); d[row.doc] = clone(row.data); write(DB_KEY, d);
        return ok();
      }
    };
  }

  // Live sync between tabs: another tab's write to localStorage arrives as a change event.
  var listeners = [];
  window.addEventListener("storage", function(e){
    if(e.key !== DB_KEY) return;
    var before = JSON.parse(e.oldValue || "{}"), after = JSON.parse(e.newValue || "{}");
    Object.keys(after).forEach(function(doc){
      if(JSON.stringify(before[doc]) !== JSON.stringify(after[doc]))
        listeners.forEach(function(cb){ cb({new: {doc: doc, writer: "another-tab"}}); });
    });
  });

  var client = {
    from: from,
    rpc: function(name, args){
      if(name !== "merge_doc") return Promise.resolve({error: {message: "unknown function " + name}});
      if(!session()) return Promise.resolve({error: denied});
      var d = db(); d[args.p_doc] = deepMerge(d[args.p_doc], args.p_patch); write(DB_KEY, d);
      return ok();
    },
    channel: function(){
      var ch = {on: function(_type, _filter, cb){ listeners.push(cb); return ch; }, subscribe: function(){ return ch; }};
      return ch;
    },
    auth: {
      getSession: function(){ return ok({session: session()}).then(function(r){ return {data: r.data, error: null}; }); },
      onAuthStateChange: function(){ return {data: {subscription: {unsubscribe: function(){}}}}; },
      signInWithPassword: function(c){ write(SESSION_KEY, {user: {id: USER.id, email: c.email}}); return ok({session: session()}); },
      signUp: function(c){ write(SESSION_KEY, {user: {id: USER.id, email: c.email}}); return ok({session: session()}); },
      // On the live site, signing out also leaves test mode (back to the real sign-in).
      signOut: function(){
        write(SESSION_KEY, null);
        if(!local){ try{ localStorage.removeItem(FLAG_KEY); }catch(e){} }
        return Promise.resolve({error: null});
      },
      resetPasswordForEmail: function(){ return ok(); },
      updateUser: function(){ return ok(); }
    }
  };

  window.turkceTestMode = {
    client: client,
    local: local,
    user: USER,
    session: session,
    db: db,
    feedback: function(){ return read(FEEDBACK_KEY, []); },
    // Start over: signed in as the Test learner with nothing saved.
    reset: function(){ [DB_KEY, SESSION_KEY, FEEDBACK_KEY].forEach(function(k){ localStorage.removeItem(k); });
      Object.keys(localStorage).filter(function(k){ return k.indexOf("fiil_") === 0; }).forEach(function(k){ localStorage.removeItem(k); }); }
  };
})();
