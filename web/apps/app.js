/* blaze_bossmenu | GNU GPL v3 (see LICENSE) | see NOTICE.md
   Boss Menu app: one page for sd-computers, sd-phone and sd-tablet (data-device on <html>).
   Every button calls the same server action the boss menu uses (server/devices.lua), so the server checks
   everything: the app can never do more than the boss menu at a desk. Opened in a normal browser it shows demo data. */
(function () {
  'use strict';

  var DEVICE = document.documentElement.getAttribute('data-device') || 'computer';
  var $ = function (s, el) { return (el || document).querySelector(s); };
  var esc = function (s) { return String(s == null ? '' : s).replace(/[&<>"']/g, function (c) { return { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]; }); };
  var arr = function (x) { return Array.isArray(x) ? x : (x && typeof x === 'object' ? Object.values(x) : []); };
  var money = function (n) { return '$' + Math.round(Number(n) || 0).toLocaleString('en-US'); };
  var initials = function (n) { return String(n || '?').split(/\s+/).filter(Boolean).slice(0, 2).map(function (w) { return w[0]; }).join('').toUpperCase(); };

  var ICON = {
    overview: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><rect x="3" y="3" width="7" height="9" rx="1.5"/><rect x="14" y="3" width="7" height="5" rx="1.5"/><rect x="14" y="12" width="7" height="9" rx="1.5"/><rect x="3" y="16" width="7" height="5" rx="1.5"/></svg>',
    staff: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><circle cx="9" cy="8" r="3.5"/><path d="M2.5 20c.8-3.5 3.4-5.5 6.5-5.5s5.7 2 6.5 5.5"/><circle cx="17.5" cy="9" r="2.5"/><path d="M17 14.5c2.3.2 4 1.9 4.5 4.5"/></svg>',
    apps: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M7 3h7l5 5v13H7z"/><path d="M14 3v5h5M10 13h6M10 17h6"/></svg>',
    funds: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M3 10l9-6 9 6M5 10v8M9.5 10v8M14.5 10v8M19 10v8M3 21h18"/></svg>',
    ranks: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M12 3l2.6 5.3 5.9.9-4.3 4.1 1 5.8L12 16.4 6.8 19.1l1-5.8L3.5 9.2l5.9-.9z"/></svg>',
    activity: '<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"><path d="M3 12h4l3-8 4 16 3-8h4"/></svg>',
  };

  // ---------------------------------------------------------------- device adapter
  var api;
  function makeApi() {
    if (DEVICE === 'computer' && window.computer && window.computer.inComputer !== false && window.parent !== window) {
      var c = window.computer;
      return {
        call: function (name, args) { return c.callServer('bm:call', { name: name, args: args || [] }).then(function (r) { return [r && r.a, r && r.b]; }); },
        notify: function (t, b) { try { c.notify({ title: t, body: b }); } catch (e) { /* ignore */ } },
        theme: c.settings && c.settings.theme,
      };
    }
    if (DEVICE === 'phone' && typeof window.fetchNui === 'function') {
      return {
        call: function (name, args) {
          return Promise.resolve(window.fetchNui('bm:call', { name: name, args: args || [] })).then(function (r) {
            if (!r || !r.ok) throw new Error((r && r.msg) || 'The server didn\'t answer.');
            return [r.a, r.b];
          });
        },
        notify: function (t, b) { try { if (window.SendNotification) window.SendNotification({ title: t, content: b }); } catch (e) { /* ignore */ } },
      };
    }
    return demoApi();
  }

  // ---------------------------------------------------------------- state
  var S = { groups: [], g: null, m: null, tab: 'overview', filter: 'open', sub: null };

  function call(name) {
    var args = Array.prototype.slice.call(arguments, 1);
    return api.call(name, args);
  }
  function result(r, okMsg) {
    var ok = r && r[0], msg = (r && r[1]) || (ok ? okMsg || 'Done.' : 'That didn\'t work.');
    toast(msg, ok ? 'good' : 'bad');
    return ok;
  }
  function failed(e) { toast((e && e.message) || String(e), 'bad'); }

  // ---------------------------------------------------------------- toasts and modals
  /** sd-phone / sd-tablet hand the keyboard to a text box on focus and back on blur. A text box that is removed
   *  while focused never blurs, which leaves the phone stuck in typing mode, so blur it first. */
  function letGo() { var a = document.activeElement; if (a && a !== document.body && a.blur) a.blur(); }
  var toastTimer;
  function toast(text, kind) {
    var t = $('#toast');
    if (!t) { t = document.createElement('div'); t.id = 'toast'; document.body.appendChild(t); }
    t.className = 'toast ' + (kind || '');
    t.textContent = text;
    t.hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(function () { t.hidden = true; }, 3200);
  }

  /** modal({ title, text, fields: [{ id, label, type, value, options, placeholder }], ok, danger }) -> Promise(values | null) */
  /** sd-phone / sd-tablet: a text box inside an app's page can't hold the keyboard (the phone takes focus back the
   *  moment it switches to typing mode), so on those devices every form uses the phone's own pop-ups instead:
   *  one pop-up per text field, the phone's list menu for a choice, a pop-up for a confirm. */
  var NATIVE = false; // set in start(): sd-phone puts SetPopUp into the page just before it says componentsLoaded
  function phoneModal(o) {
    var fields = o.fields || [];
    var out = {};
    var okColor = o.danger ? '#E5484D' : undefined;
    // the phone animates a pop-up away: opening the next one right away can leave it stuck (looks frozen)
    var pause = function () { return new Promise(function (r) { setTimeout(r, 450); }); };
    function ask(i) {
      if (i >= fields.length) return Promise.resolve(out);
      var f = fields[i], last = i === fields.length - 1;
      if (f.type === 'select') {
        var pick = typeof window.SetContextMenu === 'function' ? window.SetContextMenu : null;
        if (!pick) { out[f.id] = f.value; return ask(i + 1); }
        return Promise.resolve(pick({ title: f.label, description: i === 0 ? (o.text || o.title) : o.title,
          buttons: f.options.map(function (op) { return { title: String(op.label) }; }) })).then(function (idx) {
          if (typeof idx !== 'number' || !f.options[idx]) return null;
          out[f.id] = String(f.options[idx].value);
          return last ? out : pause().then(function () { return ask(i + 1); });
        });
      }
      var value = f.value == null ? '' : String(f.value);
      return Promise.resolve(window.SetPopUp({
        title: o.title,
        description: (i === 0 && o.text ? o.text + '\n\n' : '') + f.label,
        input: { type: f.type === 'number' ? 'number' : 'text', placeholder: f.placeholder || '', value: value, onChange: function (v) { value = v; } },
        buttons: [{ title: 'Cancel' }, { title: last ? (o.ok || 'OK') : 'Next', color: last ? okColor : undefined }],
      })).then(function (idx) {
        if (idx !== 1) return null;
        out[f.id] = value;
        return last ? out : pause().then(function () { return ask(i + 1); });
      });
    }
    if (!fields.length) {
      return Promise.resolve(window.SetPopUp({ title: o.title, description: o.text || '', buttons: [{ title: 'Cancel' }, { title: o.ok || 'OK', color: okColor }] }))
        .then(function (idx) { return idx === 1 ? {} : null; });
    }
    return ask(0);
  }

  /** sd-computers: the same idea with the desktop's own dialogs (a text box in the app page has the same focus
   *  problem as on the phone): one prompt per text field, the desktop's menu for a choice, a confirm for a yes / no. */
  function computerModal(o) {
    var c = window.computer;
    var fields = o.fields || [];
    var out = {};
    var pause = function () { return new Promise(function (r) { setTimeout(r, 300); }); };
    function ask(i) {
      if (i >= fields.length) return Promise.resolve(out);
      var f = fields[i], last = i === fields.length - 1;
      var next = function () { return last ? out : pause().then(function () { return ask(i + 1); }); };
      if (f.type === 'select') {
        var items = f.options.map(function (op) { return { id: String(op.value), label: String(op.label) }; });
        return Promise.resolve(c.menu({ x: Math.round(window.innerWidth / 2 - 110), y: Math.round(window.innerHeight / 3), items: items })).then(function (id) {
          if (id == null) return null;
          out[f.id] = String(id);
          return next();
        });
      }
      return Promise.resolve(c.dialog.prompt({
        title: o.title, message: (i === 0 && o.text ? o.text + '\n\n' : '') + f.label,
        value: f.value == null ? '' : String(f.value), placeholder: f.placeholder || '',
        confirmLabel: last ? (o.ok || 'OK') : 'Next', cancelLabel: 'Cancel', danger: last && !!o.danger,
      })).then(function (v) {
        if (v == null) return null;
        out[f.id] = String(v);
        return next();
      });
    }
    if (!fields.length) {
      return Promise.resolve(c.dialog.confirm({ title: o.title, message: o.text || '', confirmLabel: o.ok || 'OK', cancelLabel: 'Cancel', danger: !!o.danger }))
        .then(function (yes) { return yes ? {} : null; });
    }
    return ask(0);
  }

  function modal(o) {
    if (NATIVE === 'phone') return phoneModal(o);
    if (NATIVE === 'computer') return computerModal(o);
    return new Promise(function (resolve) {
      var shade = document.createElement('div');
      shade.className = 'shade';
      var fields = (o.fields || []).map(function (f) {
        var input;
        if (f.type === 'select') {
          input = '<select data-id="' + f.id + '">' + f.options.map(function (op) {
            return '<option value="' + esc(op.value) + '"' + (String(op.value) === String(f.value) ? ' selected' : '') + '>' + esc(op.label) + '</option>';
          }).join('') + '</select>';
        } else if (f.type === 'textarea') {
          input = '<textarea data-id="' + f.id + '" placeholder="' + esc(f.placeholder || '') + '">' + esc(f.value || '') + '</textarea>';
        } else {
          input = '<input data-id="' + f.id + '" type="' + (f.type || 'text') + '" value="' + esc(f.value == null ? '' : f.value) + '" placeholder="' + esc(f.placeholder || '') + '">';
        }
        return '<label>' + esc(f.label) + '</label>' + input;
      }).join('');
      shade.innerHTML = '<div class="modal"><h3>' + esc(o.title) + '</h3>' + (o.text ? '<p>' + esc(o.text) + '</p>' : '') + fields +
        '<div class="acts"><button class="btn" data-a="no">Cancel</button><button class="btn ' + (o.danger ? 'bad' : 'pri') + '" data-a="yes">' + esc(o.ok || 'OK') + '</button></div></div>';
      document.body.appendChild(shade);
      // computer: put the cursor in the first box. Phone / tablet: wait for a tap, since a focused text box switches
      // the character into sd-phone's typing pose (and the keyboard to the phone).
      var first = shade.querySelector('input, select, textarea');
      if (first && DEVICE !== 'phone') first.focus();
      function done(yes) {
        var out = null;
        if (yes) {
          out = {};
          shade.querySelectorAll('[data-id]').forEach(function (el) { out[el.getAttribute('data-id')] = el.value; });
        }
        letGo();
        shade.remove();
        resolve(out);
      }
      shade.addEventListener('click', function (e) {
        var a = e.target.getAttribute && e.target.getAttribute('data-a');
        if (a) done(a === 'yes');
        else if (e.target === shade) done(false);
      });
      shade.addEventListener('keydown', function (e) {
        if (e.key === 'Escape') done(false);
        if (e.key === 'Enter' && e.target.tagName !== 'TEXTAREA') done(true);
      });
    });
  }

  // ---------------------------------------------------------------- loading
  function loadGroups() {
    return call('getMyJobs').then(function (r) {
      S.groups = arr(r[0] && r[0].groups);
      if (!S.g || !S.groups.some(function (g) { return g.gtype === S.g.gtype && g.name === S.g.name; })) S.g = S.groups[0] || null;
    });
  }
  function loadMenu() {
    if (!S.g) { S.m = null; return Promise.resolve(); }
    return call('getMenu', S.g.gtype, S.g.name).then(function (r) { S.m = r[0] || null; });
  }
  function refresh() {
    return loadGroups().then(loadMenu).then(render).catch(function (e) { noAccess((e && e.message) || String(e)); });
  }

  /** Full screen "no access": not a manager, the app is turned off, or the server refused */
  function noAccess(reason) {
    S.g = null; S.m = null;
    var app = $('#app');
    app.innerHTML = '<header class="top"><img src="icon.png" alt=""><div class="t"><h1>Boss Menu</h1><p>Blaze Boss Menu</p></div>' +
      '<button class="refresh" id="refresh" title="Try again">&#x21bb;</button></header>' +
      '<div class="main"><div class="notice"><b>You don\'t have access to the Boss Menu.</b>' +
      '<small>' + esc(reason || 'Only managers of a job or gang can use it: the same people who can open that job\'s boss desk.') + '</small></div></div>';
    $('#refresh').onclick = function () { refresh(); };
  }

  // ---------------------------------------------------------------- shell
  function wide() { var a = $('#app'); return !!a && !a.classList.contains('narrow'); }
  function render() {
    var app = $('#app');
    letGo();
    if (!S.g || !S.m) return noAccess(); // not a manager of anything (the server decides)
    var tabs = [['overview', 'Overview'], ['staff', S.g.gtype === 'gang' ? 'Members' : 'Staff']];
    if (S.m.apps) tabs.push(['apps', 'Applications']);
    if (S.m.funds) tabs.push(['funds', 'Funds']);
    if (S.m.gradeEdit) tabs.push(['ranks', 'Ranks']);
    tabs.push(['activity', 'Activity']);
    if (!tabs.some(function (t) { return t[0] === S.tab; })) S.tab = 'overview';
    app.innerHTML = head() + '<div class="body"><nav class="nav">' + tabs.map(function (t) {
      var count = t[0] === 'apps' && S.m.newApps > 0 ? '<span class="count">' + S.m.newApps + '</span>' : '';
      return '<button data-tab="' + t[0] + '" class="' + (S.tab === t[0] ? 'on' : '') + '">' + ICON[t[0]] + '<span>' + t[1] + '</span>' + count + '</button>';
    }).join('') + '</nav><div class="main" id="main"><div class="loading">Loading…</div></div></div>';
    wireHead();
    app.querySelectorAll('[data-tab]').forEach(function (b) {
      b.onclick = function () { S.tab = b.getAttribute('data-tab'); S.sub = null; render(); };
    });
    var view = { overview: overview, staff: staff, apps: apps, funds: funds, ranks: ranks, activity: activity }[S.tab];
    Promise.resolve().then(view).catch(failed);
  }
  function head() {
    var sel = S.groups.length > 1 ? '<select id="pick">' + S.groups.map(function (g, i) {
      return '<option value="' + i + '"' + (S.g && g.name === S.g.name && g.gtype === S.g.gtype ? ' selected' : '') + '>' + esc(g.label) + '</option>';
    }).join('') + '</select>' : '';
    var sub = S.m ? (S.g.gtype === 'gang' ? 'Gang management' : 'Department management') : 'Blaze Boss Menu';
    return '<header class="top"><img src="icon.png" alt=""><div class="t"><h1>' + esc(S.m ? S.m.label : 'Boss Menu') + '</h1><p>' + sub + '</p></div>' +
      sel + '<button class="refresh" id="refresh" title="Refresh">&#x21bb;</button></header>';
  }
  function wireHead() {
    var pick = $('#pick');
    if (pick) pick.onchange = function () { S.g = S.groups[Number(pick.value)]; S.tab = 'overview'; S.sub = null; loadMenu().then(render).catch(failed); };
    $('#refresh').onclick = function () { refresh(); };
  }
  function main(html) { letGo(); var m = $('#main'); if (m) m.innerHTML = html; return m; }
  /** Tablet / computer: a list on the left and what's open on the right. Phone: one screen at a time. */
  function split(listHtml, detailHtml) {
    return '<div class="split"><div class="split-list">' + listHtml + '</div><div class="split-detail" id="detail">' + detailHtml + '</div></div>';
  }
  function pane(html) { letGo(); var d = $('#detail'); if (d) { d.innerHTML = html; return d; } return main(html); }
  function pickHint(text) { return '<div class="pick-hint">' + esc(text) + '</div>'; }

  // ---------------------------------------------------------------- overview
  function overview() {
    var g = S.g;
    var jobs = [call('getStaff', g.gtype, g.name), call('getAnnouncement', g.gtype, g.name)];
    if (g.gtype === 'job' && S.m.funds) jobs.push(call('getPayroll', g.gtype, g.name));
    return Promise.all(jobs).then(function (r) {
      var members = arr(r[0][0] && r[0][0].members);
      var onDuty = members.filter(function (m) { return m.onduty; });
      var star = members.find(function (m) { return m.eotw; });
      var ann = r[1][0];
      var pay = r[2] && r[2][0];
      var stats = '<div class="stat"><small>' + (g.gtype === 'gang' ? 'Members' : 'Staff') + '</small><b>' + members.length + '</b></div>' +
        (g.gtype === 'job' ? '<div class="stat"><small>On duty</small><b class="green">' + onDuty.length + '</b></div>' : '') +
        (S.m.apps ? '<div class="stat"><small>New applications</small><b>' + (S.m.newApps || 0) + '</b></div>' : '') +
        (S.m.funds ? '<div class="stat"><small>Balance</small><b class="money">' + money(S.m.balance) + '</b></div>' : '') +
        (pay && wide() ? '<div class="stat"><small>Payroll per paycheck</small><b class="money">' + money(pay.perPaycheckOnDuty) + '</b><span class="mini">' + money(pay.perPaycheckAll) + ' if everyone is on duty</span></div>' : '') +
        (star ? '<div class="stat"><small>Employee of the week</small><b class="name">&#9733; ' + esc(star.name) + '</b></div>' : '');
      var annHtml = ann && ann.message
        ? '<div class="notice">' + esc(ann.message) + '<small>' + esc(ann.by_name || 'Management') + (ann.at ? ' · ' + esc(ann.at) : '') + '</small></div>'
        : '<div class="notice" style="color:var(--faint)">No announcement.</div>';
      var m = main('<div class="section"><div class="stats">' + stats + '</div></div>' +
        '<div class="cols"><div class="section"><div class="bar"><h2 class="grow" style="margin:0">Announcement</h2><button class="btn" id="annEdit">Edit</button></div>' + annHtml + '</div>' +
        (g.gtype === 'job' ? '<div class="section"><h2>On duty now</h2><div class="list">' + (onDuty.length ? onDuty.map(personRow).join('') : '<div class="empty">Nobody is on duty.</div>') + '</div></div>' : '') +
        '</div>');
      $('#annEdit', m).onclick = function () {
        modal({ title: 'Announcement', text: 'Staff see it right away, and when they clock in. Leave it empty to clear it.', ok: 'Post',
          fields: [{ id: 'msg', label: 'Message', type: 'textarea', value: ann && ann.message }] }).then(function (v) {
          if (!v) return;
          return call('postAnnouncement', g.gtype, g.name, v.msg.trim()).then(function (res) { if (result(res)) render(); });
        }).catch(failed);
      };
      m.querySelectorAll('[data-cid]').forEach(function (row) { row.onclick = function () { S.tab = 'staff'; S.sub = row.getAttribute('data-cid'); render(); }; });
    });
  }

  // ---------------------------------------------------------------- staff
  function badges(m) {
    var t = [];
    if (m.isSelf) t.push('<span class="tag blue">You</span>');
    if (m.eotw) t.push('<span class="tag amber">Employee of the week</span>');
    if (m.probationDays) t.push('<span class="tag amber">Probation · ' + m.probationDays + 'd</span>');
    if (m.readyForPromotion) t.push('<span class="tag green">Ready for promotion</span>');
    if (m.inactive) t.push('<span class="tag red">Inactive</span>');
    return t.join('');
  }
  function personRow(m) {
    return '<div class="row' + (m.citizenid ? ' click' : '') + (S.sub && S.sub === m.citizenid ? ' sel' : '') + '" data-cid="' + esc(m.citizenid) + '"><div class="av">' + esc(initials(m.name)) +
      '<i class="' + (m.onduty ? 'on' : '') + '"></i></div><div class="who"><b>' + esc(m.name) + '</b><small>' + esc(m.gradeName || ('Rank ' + m.grade)) +
      (m.callsign ? ' · ' + esc(m.callsign) : '') + (m.hours != null ? ' · ' + Number(m.hours).toFixed(1) + ' h' : '') + '</small></div><div class="side">' + badges(m) + '</div></div>';
  }
  function staff() {
    var g = S.g;
    return call('getStaff', g.gtype, g.name).then(function (r) {
      var d = r[0] || {};
      var members = arr(d.members), grades = arr(d.grades), limit = d.limit;
      var m = S.sub && members.find(function (x) { return x.citizenid === S.sub; });
      if (S.sub && !m) S.sub = null;
      var listHtml = '<div class="bar"><h2 class="grow" style="margin:0">' + members.length + ' ' + (g.gtype === 'gang' ? 'members' : 'staff') + '</h2>' +
        '<button class="btn pri" id="hire">Hire</button></div><div class="list">' + (members.length ? members.map(personRow).join('') : '<div class="empty">Nobody yet.</div>') + '</div>';
      var el;
      if (wide()) el = main(split(listHtml, m ? '<div class="loading">Loading…</div>' : pickHint('Pick someone to see their profile and manage them.')));
      else if (m) return member(m, grades, limit);
      else el = main(listHtml);
      el.querySelectorAll('.split-list [data-cid], .main > .list [data-cid], #main > .list [data-cid]').forEach(function (row) {
        row.onclick = function () { S.sub = row.getAttribute('data-cid'); staff().catch(failed); };
      });
      if (!wide()) el.querySelectorAll('[data-cid]').forEach(function (row) { row.onclick = function () { S.sub = row.getAttribute('data-cid'); staff().catch(failed); }; });
      $('#hire', el).onclick = function () {
        var opts = grades.filter(function (gr) { return gr.level < limit; }).map(function (gr) { return { value: gr.level, label: gr.name }; });
        if (!opts.length) return toast('You can\'t hire for any rank.', 'bad');
        modal({ title: 'Hire', text: 'They must be online and standing near you. They get a contract to sign.', ok: 'Send offer',
          fields: [{ id: 'id', label: 'Server ID', type: 'number', placeholder: 'e.g. 12' }, { id: 'grade', label: 'Rank', type: 'select', options: opts, value: opts[0].value }] })
          .then(function (v) {
            if (!v) return;
            toast('Offer sent. Waiting for them to sign…');
            return call('hire', g.gtype, g.name, Number(v.id), Number(v.grade)).then(function (res) { if (result(res)) staff(); });
          }).catch(failed);
      };
      if (m) return member(m, grades, limit);
    });
  }
  function member(m, grades, limit) {
    var g = S.g;
    return call('getProfile', g.gtype, g.name, m.citizenid).then(function (r) {
      var p = r[0] || {};
      var manage = !m.isSelf && m.grade < limit;
      var next = grades.find(function (gr) { return gr.level === m.grade + 1; });
      var records = arr(p.records);
      var kv = function (k, v) { return v == null || v === '' ? '' : '<span>' + k + '</span><span>' + v + '</span>'; };
      var el = pane((wide() ? '' : '<button class="back" id="back">&#8592; ' + (g.gtype === 'gang' ? 'Members' : 'Staff') + '</button>') +
        '<div class="profile"><div class="av big">' + esc(initials(m.name)) + '<i class="' + (m.onduty ? 'on' : '') + '"></i></div><div><b>' + esc(m.name) + '</b><small>' +
        esc(m.gradeName) + (m.callsign ? ' · ' + esc(m.callsign) : '') + '</small><div>' + badges(m) + '</div></div></div>' +
        '<div class="section"><div class="kv">' +
        kv('Status', m.onduty ? 'On duty' : (m.online ? 'Online, off duty' : 'Offline')) +
        kv('Hired', esc(p.hiredAt || m.hiredAt)) +
        kv('Probation until', esc(p.probationUntil)) +
        kv('Hours this week', p.hoursWeek != null ? Number(p.hoursWeek).toFixed(1) : '') +
        kv('Hours (last 31 days)', m.hours != null ? Number(m.hours).toFixed(1) : '') +
        kv('Last clock-in', esc(p.lastCheckin)) +
        kv('Phone', esc(p.phone)) + kv('Email', esc(p.email)) +
        kv('Record', (p.commendations || 0) + ' commendations · ' + (p.warnings || 0) + ' write-ups') +
        kv('Contracts', arr(p.contracts).length ? arr(p.contracts).map(function (c) { return esc(c.number || ('#' + c.id)) + ' (' + esc(c.at) + ')'; }).join(', ') : '') +
        '</div></div>' +
        '<div class="section"><h2>Manage</h2><div class="bar">' +
        '<button class="btn good" id="promote"' + (manage && next && next.level < limit ? '' : ' disabled') + '>Promote' + (next ? ' to ' + esc(next.name) : '') + '</button>' +
        '<button class="btn" id="demote"' + (manage && m.grade > 0 ? '' : ' disabled') + '>Demote</button>' +
        (S.m.callsigns ? '<button class="btn" id="callsign"' + (manage || m.isSelf ? '' : ' disabled') + '>Callsign</button>' : '') +
        '<button class="btn bad" id="fire"' + (manage ? '' : ' disabled') + '>' + (g.gtype === 'gang' ? 'Kick' : 'Fire') + '</button></div>' +
        '<div class="bar"><button class="btn good" id="commend"' + (m.isSelf ? ' disabled' : '') + '>Commend</button>' +
        '<button class="btn" id="writeup"' + (manage ? '' : ' disabled') + '>Write up</button>' +
        '<button class="btn" id="eotw"' + (m.isSelf || m.eotw ? ' disabled' : '') + '>&#9733; Employee of the week</button>' +
        (S.m.funds ? '<button class="btn" id="bonus"' + (m.isSelf || !m.online ? ' disabled' : '') + '>Bonus</button>' : '') + '</div>' +
        (manage ? '' : '<p class="hint">' + (m.isSelf ? 'This is you.' : 'You can only manage people below your rank.') + '</p>') + '</div>' +
        '<div class="section"><h2>Record</h2><div class="list">' + (records.length ? records.map(function (x) {
          var good = x.type === 'commend';
          return '<div class="row"><div class="who"><b style="white-space:normal">' + esc(x.text) + '</b><small>' + esc(x.by_name || '') + '</small></div><div class="side"><span class="tag ' +
            (good ? 'green">Commendation' : 'red">Write-up') + '</span><br>' + esc(x.at || '') + '</div></div>';
        }).join('') : '<div class="empty">Nothing on record.</div>') + '</div></div>');
      var again = function () { staff().catch(failed); };
      var back = $('#back', el);
      if (back) back.onclick = function () { S.sub = null; again(); };
      var go = function (name) { var a = Array.prototype.slice.call(arguments, 1); return api.call(name, a).then(function (res) { result(res); again(); }); };
      $('#promote', el).onclick = function () { go('promote', g.gtype, g.name, m.citizenid).catch(failed); };
      $('#demote', el).onclick = function () { go('demote', g.gtype, g.name, m.citizenid).catch(failed); };
      var cs = $('#callsign', el);
      if (cs) cs.onclick = function () {
        modal({ title: 'Callsign', ok: 'Save', fields: [{ id: 'cs', label: 'Callsign (empty = remove)', value: m.callsign || '' }] })
          .then(function (v) { if (v) return go('setCallsign', g.gtype, g.name, m.citizenid, v.cs.trim()); }).catch(failed);
      };
      $('#fire', el).onclick = function () {
        modal({ title: (g.gtype === 'gang' ? 'Kick ' : 'Fire ') + m.name + '?', text: 'They lose the ' + (g.gtype === 'gang' ? 'gang' : 'job') + ' and its access right away.', ok: g.gtype === 'gang' ? 'Kick' : 'Fire', danger: true })
          .then(function (v) { if (v) return api.call('fire', [g.gtype, g.name, m.citizenid]).then(function (res) { if (result(res)) S.sub = null; again(); }); }).catch(failed);
      };
      var record = function (kind) {
        modal({ title: kind === 'commend' ? 'Commend ' + m.name : 'Write up ' + m.name, ok: kind === 'commend' ? 'Commend' : 'Write up', danger: kind !== 'commend',
          text: kind === 'commend' ? 'Goes on their record, and they get a message.' : 'Goes on their record, and they get a message.',
          fields: [{ id: 'text', label: kind === 'commend' ? 'What for' : 'What happened', type: 'textarea' }] })
          .then(function (v) { if (v) return go('addRecord', g.gtype, g.name, m.citizenid, kind, v.text.trim()); }).catch(failed);
      };
      $('#commend', el).onclick = function () { record('commend'); };
      $('#writeup', el).onclick = function () { record('warning'); };
      $('#eotw', el).onclick = function () {
        modal({ title: 'Employee of the week', text: m.name + ' is shown to the whole department this week.', ok: 'Pick', fields: [{ id: 'why', label: 'Why (optional)' }] })
          .then(function (v) { if (v) return go('setEmployeeOfWeek', g.gtype, g.name, m.citizenid, v.why.trim()); }).catch(failed);
      };
      var bonus = $('#bonus', el);
      if (bonus) bonus.onclick = function () {
        modal({ title: 'Bonus for ' + m.name, text: 'Paid from the society account into their bank.', ok: 'Pay',
          fields: [{ id: 'amount', label: 'Amount', type: 'number' }, { id: 'reason', label: 'Reason' }] })
          .then(function (v) { if (v) return go('bonus', g.gtype, g.name, 'one', m.citizenid, Math.floor(Number(v.amount)), v.reason.trim()); }).catch(failed);
      };
    });
  }

  // ---------------------------------------------------------------- applications
  var STATUS = { new: ['New', 'blue'], interview: ['Interview', 'amber'], accepted: ['Accepted', 'green'], denied: ['Denied', 'red'], withdrawn: ['Withdrawn', ''] };
  function apps() {
    var job = S.g.name;
    if (S.sub && !wide()) return application(job, S.sub);
    return call('getApplications', job, S.filter === 'open' ? null : S.filter).then(function (r) {
      var rows = arr(r[0]);
      var f = [['open', 'Open'], ['accepted', 'Accepted'], ['denied', 'Denied'], ['withdrawn', 'Withdrawn']];
      var listHtml = '<div class="bar"><div class="seg">' + f.map(function (x) { return '<button data-f="' + x[0] + '" class="' + (S.filter === x[0] ? 'on' : '') + '">' + x[1] + '</button>'; }).join('') +
        '</div><span class="grow"></span><button class="btn ' + (S.m.appsOpen ? 'bad' : 'good') + '" id="toggle">' + (S.m.appsOpen ? 'Close' : 'Open') + ' applications</button></div>' +
        '<div class="list">' + (rows.length ? rows.map(function (a) {
          var st = STATUS[a.status] || [a.status, ''];
          return '<div class="row click' + (S.sub === a.id ? ' sel' : '') + '" data-id="' + a.id + '"><div class="av">' + esc(initials(a.name)) + '</div><div class="who"><b>' + esc(a.name) + '</b><small>Sent ' + esc(a.created) +
            '</small></div><div class="side"><span class="tag ' + st[1] + '">' + st[0] + '</span></div></div>';
        }).join('') : '<div class="empty">No applications here.</div>') + '</div>';
      var el = wide() ? main(split(listHtml, S.sub ? '<div class="loading">Loading…</div>' : pickHint('Pick an application to read it and decide.'))) : main(listHtml);
      el.querySelectorAll('[data-f]').forEach(function (b) { b.onclick = function () { S.filter = b.getAttribute('data-f'); S.sub = null; apps().catch(failed); }; });
      el.querySelectorAll('[data-id]').forEach(function (row) { row.onclick = function () { S.sub = Number(row.getAttribute('data-id')); apps().catch(failed); }; });
      $('#toggle', el).onclick = function () {
        call('toggleApplications', job).then(function (res) { result(res); return loadMenu(); }).then(render).catch(failed);
      };
      if (S.sub) return application(job, S.sub);
    });
  }
  function application(job, id) {
    return Promise.all([call('getApplication', job, id), call('getStaff', S.g.gtype, S.g.name)]).then(function (r) {
      var a = r[0][0];
      if (!a) { S.sub = null; return apps(); }
      var grades = arr(r[1][0] && r[1][0].grades), limit = r[1][0] && r[1][0].limit;
      var st = STATUS[a.status] || [a.status, ''];
      var open = a.status === 'new' || a.status === 'interview';
      var answers = arr(a.answers).map(function (q) {
        var v = q.type === 'checkbox' ? (q.answer ? 'Yes' : 'No') : (q.answer == null || q.answer === '' ? '—' : q.answer);
        return '<div class="answer"><small>' + esc(q.label) + '</small><p>' + esc(v) + '</p></div>';
      }).join('');
      var votes = a.votes ? '<div class="bar"><span class="tag green">' + a.votes.up + ' for</span><span class="tag red">' + a.votes.down + ' against</span><span class="grow"></span>' +
        '<button class="btn good" data-vote="1"' + (a.votes.mine === 1 ? ' disabled' : '') + '>Vote for</button><button class="btn bad" data-vote="-1"' + (a.votes.mine === -1 ? ' disabled' : '') + '>Vote against</button></div>' : '';
      var el = pane((wide() ? '' : '<button class="back" id="back">&#8592; Applications</button>') +
        '<div class="bar"><h2 class="grow" style="margin:0;text-transform:none;letter-spacing:0;font-size:16px;color:var(--text)">' + esc(a.name) + '</h2><span class="tag ' + st[1] + '">' + esc(a.statusLabel || st[0]) + '</span></div>' +
        (a.reviewed_by ? '<p class="hint" style="margin:-4px 0 12px">Last update by ' + esc(a.reviewed_by) + '</p>' : '') +
        (a.deny_reason ? '<div class="notice" style="margin-bottom:12px">Denied: ' + esc(a.deny_reason) + '</div>' : '') +
        (a.interview_msg ? '<div class="notice" style="margin-bottom:12px">Interview: ' + esc(a.interview_msg) + '</div>' : '') +
        votes + '<div class="section">' + (answers || '<div class="empty">No answers.</div>') + '</div>' +
        (open ? '<div class="section"><div class="bar"><button class="btn pri" id="accept">Accept &amp; hire</button><button class="btn" id="interview">Invite to interview</button><button class="btn bad" id="deny">Deny</button></div></div>' : '') +
        '<div class="section"><h2>Manager notes</h2>' + (NATIVE
          ? '<div class="notice">' + (a.notes ? esc(a.notes) : '<span style="color:var(--faint)">No notes yet. Only managers see these.</span>') + '</div>' +
            '<div class="bar" style="margin-top:8px"><span class="grow"></span><button class="btn" id="editNotes">Edit notes</button></div>'
          : '<textarea class="notes" id="notes" placeholder="Only managers see these.">' + esc(a.notes || '') + '</textarea>' +
            '<div class="bar" style="margin-top:8px"><span class="grow"></span><button class="btn" id="saveNotes">Save notes</button></div>') + '</div>');
      var back = function () { S.sub = null; loadMenu().then(render).catch(failed); };
      var again = function () { application(job, id).catch(failed); };
      var bb = $('#back', el);
      if (bb) bb.onclick = back;
      el.querySelectorAll('[data-vote]').forEach(function (b) {
        b.onclick = function () { call('voteApplication', job, id, Number(b.getAttribute('data-vote'))).then(function (res) { result(res, 'Vote saved.'); again(); }).catch(failed); };
      });
      if (NATIVE) {
        $('#editNotes', el).onclick = function () {
          modal({ title: 'Manager notes', text: 'Only managers see these.', ok: 'Save', fields: [{ id: 'notes', label: 'Notes', type: 'textarea', value: a.notes || '' }] })
            .then(function (v) { if (v) return call('saveNote', job, id, v.notes).then(function (res) { result(res, 'Notes saved.'); again(); }); }).catch(failed);
        };
      } else {
        var notes = $('#notes', el);
        $('#saveNotes', el).onclick = function () { call('saveNote', job, id, notes.value).then(function (res) { result(res, 'Notes saved.'); }).catch(failed); };
      }
      if (!open) return;
      $('#accept', el).onclick = function () {
        var opts = grades.filter(function (gr) { return gr.level < limit; }).map(function (gr) { return { value: gr.level, label: gr.name }; });
        modal({ title: 'Accept ' + a.name, text: 'They get a contract to sign with this rank.', ok: 'Accept', fields: [{ id: 'grade', label: 'Rank', type: 'select', options: opts, value: opts[0] && opts[0].value }] })
          .then(function (v) { if (!v) return; return call('accept', job, id, Number(v.grade)).then(function (res) { if (result(res)) back(); }); }).catch(failed);
      };
      $('#interview', el).onclick = function () {
        modal({ title: 'Invite to interview', ok: 'Send', fields: [{ id: 'msg', label: 'Message to ' + a.name, type: 'textarea', placeholder: 'When and where to come' }] })
          .then(function (v) { if (!v) return; return call('interview', job, id, v.msg.trim()).then(function (res) { result(res); again(); }); }).catch(failed);
      };
      $('#deny', el).onclick = function () {
        modal({ title: 'Deny ' + a.name, ok: 'Deny', danger: true, fields: [{ id: 'reason', label: 'Reason (they see this)', type: 'textarea' }] })
          .then(function (v) { if (!v) return; return call('deny', job, id, v.reason.trim()).then(function (res) { if (result(res)) back(); }); }).catch(failed);
      };
    });
  }

  // ---------------------------------------------------------------- funds
  function funds() {
    var g = S.g;
    var jobs = [call('getFunds', g.gtype, g.name)];
    if (g.gtype === 'job') jobs.push(call('getPayroll', g.gtype, g.name));
    return Promise.all(jobs).then(function (r) {
      var d = r[0][0];
      if (!d) return main('<div class="notice">' + esc(r[0][1] || 'Funds aren\'t available.') + '</div>');
      var hist = arr(d.history);
      var pay = r[1] && r[1][0];
      var payroll = pay ? '<div class="section"><h2>Payroll</h2><div class="list">' + arr(pay.grades).map(function (gr) {
        return '<div class="row"><div class="who"><b>' + esc(gr.name) + '</b><small>' + gr.members + ' ' + (gr.members === 1 ? 'person' : 'people') + ' · ' + gr.onduty + ' on duty</small></div>' +
          '<div class="side money">' + money(gr.pay) + '</div></div>';
      }).join('') + '<div class="row total"><div class="who"><b>Per paycheck</b><small>' + money(pay.perPaycheckAll) + ' if everyone is on duty</small></div><div class="side money">' + money(pay.perPaycheckOnDuty) + '</div></div></div></div>' : '';
      var recent = '<div class="section"><h2>Recent</h2><div class="list">' + (hist.length ? hist.map(function (h) {
        var plus = h.type === 'deposit';
        return '<div class="row"><div class="who"><b class="money ' + (plus ? 'plus' : 'minus') + '">' + (plus ? '+ ' : '- ') + money(h.amount) + '</b><small>' + esc(h.reason || h.type) +
          '</small></div><div class="side">' + esc(h.name || '') + '<br>' + esc(h.at || '') + '</div></div>';
      }).join('') : '<div class="empty">Nothing yet.</div>') + '</div></div>';
      var el = main('<div class="section"><div class="stats"><div class="stat"><small>Balance</small><b class="money">' + money(d.balance) + '</b></div>' +
        (d.left != null ? '<div class="stat"><small>You can still take out today</small><b class="money">' + money(d.left) + '</b></div>' : '') + '</div></div>' +
        '<div class="section"><div class="bar"><button class="btn good" id="dep">Deposit cash</button><button class="btn" id="wd">Withdraw</button>' +
        '<button class="btn" id="bonusAll">Bonus everyone on duty</button></div></div>' +
        (wide() && payroll ? '<div class="cols">' + recent + payroll + '</div>' : recent + payroll));
      function move(kind) {
        modal({ title: kind === 'deposit' ? 'Deposit cash' : 'Withdraw', ok: kind === 'deposit' ? 'Deposit' : 'Withdraw',
          fields: [{ id: 'amount', label: 'Amount', type: 'number', placeholder: '0' }, { id: 'reason', label: 'Reason', placeholder: 'What it\'s for' }] })
          .then(function (v) {
            if (!v) return;
            var amount = Math.floor(Number(v.amount));
            var go = function () { return call(kind, g.gtype, g.name, amount, v.reason.trim()).then(function (res) { result(res); return loadMenu(); }).then(render); };
            if (kind === 'withdraw' && amount > (d.confirmAbove || 5000)) {
              return modal({ title: 'Withdraw ' + money(amount) + '?', text: 'That\'s a big amount. It comes out of the society account.', ok: 'Withdraw', danger: true })
                .then(function (ok) { if (ok) return go(); });
            }
            return go();
          }).catch(failed);
      }
      $('#dep', el).onclick = function () { move('deposit'); };
      $('#wd', el).onclick = function () { move('withdraw'); };
      $('#bonusAll', el).onclick = function () {
        modal({ title: 'Bonus everyone on duty', text: 'Each person on duty (not you) gets this amount in their bank, from the society account.', ok: 'Pay',
          fields: [{ id: 'amount', label: 'Amount per person', type: 'number' }, { id: 'reason', label: 'Reason' }] })
          .then(function (v) {
            if (!v) return;
            return call('bonus', g.gtype, g.name, 'all', null, Math.floor(Number(v.amount)), v.reason.trim()).then(function (res) { result(res); return loadMenu(); }).then(render);
          }).catch(failed);
      };
    });
  }

  // ---------------------------------------------------------------- ranks (rank editor turned on)
  function ranks() {
    var g = S.g;
    return call('getStaff', g.gtype, g.name).then(function (r) {
      var d = r[0] || {};
      var grades = arr(d.grades), limit = d.limit, own = S.m.ownGrade;
      var count = {};
      arr(d.members).forEach(function (m) { count[m.grade] = (count[m.grade] || 0) + 1; });
      var el = main('<h2>Ranks</h2><div class="list">' + grades.slice().reverse().map(function (gr) {
        var can = gr.level < limit || gr.level === own;
        return '<div class="row' + (can ? ' click' : '') + '" data-lvl="' + gr.level + '"><div class="av">' + gr.level + '</div><div class="who"><b>' + esc(gr.name) + '</b><small>' +
          (count[gr.level] || 0) + ' ' + ((count[gr.level] || 0) === 1 ? 'person' : 'people') + (g.gtype === 'job' && gr.payment != null ? ' · ' + money(gr.payment) + ' per paycheck' : '') +
          '</small></div><div class="side">' + (gr.isboss ? '<span class="tag purple">Boss</span>' : '') + (gr.bankAuth ? '<span class="tag blue">Bank</span>' : '') + '</div></div>';
      }).join('') + '</div><p class="hint">Changes are saved in the framework and kept across restarts. You can edit ranks below yours, and your own.</p>');
      el.querySelectorAll('.row.click').forEach(function (row) {
        row.onclick = function () {
          var gr = grades.find(function (x) { return x.level === Number(row.getAttribute('data-lvl')); });
          var yes = [{ value: '1', label: 'Yes' }, { value: '0', label: 'No' }];
          var fields = [{ id: 'name', label: 'Rank name', value: gr.name }];
          if (g.gtype === 'job') fields.push({ id: 'pay', label: 'Pay per paycheck', type: 'number', value: gr.payment });
          fields.push({ id: 'boss', label: 'Boss access (can open the boss menu)', type: 'select', options: yes, value: gr.isboss ? '1' : '0' });
          if (g.gtype === 'job') fields.push({ id: 'bank', label: 'Bank access (society account)', type: 'select', options: yes, value: gr.bankAuth ? '1' : '0' });
          modal({ title: 'Edit rank ' + gr.level, ok: 'Save', fields: fields }).then(function (v) {
            if (!v) return;
            var data = { name: v.name.trim(), isboss: v.boss === '1' };
            if (g.gtype === 'job') { data.payment = Number(v.pay); data.bankAuth = v.bank === '1'; }
            return call('modifyGrade', g.gtype, g.name, gr.level, data).then(function (res) { result(res); ranks(); });
          }).catch(failed);
        };
      });
    });
  }

  // ---------------------------------------------------------------- activity
  function activity() {
    return call('getAudit', S.g.gtype, S.g.name).then(function (r) {
      var rows = arr(r[0]);
      main('<h2>Recent activity</h2><div class="list">' + (rows.length ? rows.map(function (x) {
        return '<div class="row"><div class="who"><b style="white-space:normal">' + esc(x.message || x.event) + '</b><small>' + esc(x.actor || 'system') + '</small></div><div class="side">' + esc(x.at || '') + '</div></div>';
      }).join('') : '<div class="empty">' + (r[0] ? 'Nothing yet.' : 'The activity log is turned off.') + '</div>') + '</div>');
    });
  }

  // ---------------------------------------------------------------- demo data (normal browser)
  function demoApi() {
    var staffList = [
      { citizenid: 'A1', name: 'Dr. Steven Blaze', grade: 5, gradeName: 'Chief', callsign: 'E-01', onduty: true, online: true, hours: 41.5, isSelf: true, eotw: true },
      { citizenid: 'A2', name: 'Jane Doe', grade: 2, gradeName: 'Paramedic', callsign: 'E-14', onduty: true, online: true, hours: 14.5, probationDays: 3 },
      { citizenid: 'A3', name: 'Mike Kerr', grade: 1, gradeName: 'EMT', callsign: 'E-22', onduty: true, online: true, hours: 9 },
      { citizenid: 'A4', name: 'Ana Lopez', grade: 2, gradeName: 'Paramedic', callsign: 'E-17', onduty: false, online: true, hours: 22, readyForPromotion: true },
      { citizenid: 'A5', name: 'Chris Vale', grade: 3, gradeName: 'Senior Paramedic', onduty: false, online: false, hours: 0, inactive: true },
    ];
    var grades = ['Probationary EMT', 'EMT', 'Paramedic', 'Senior Paramedic', 'Supervisor', 'Chief'].map(function (n, i) { return { level: i, name: n, payment: 250 + i * 150, isboss: i >= 4, bankAuth: i >= 5 }; });
    var D = {
      getMyJobs: [{ groups: [{ gtype: 'job', name: 'ambulance', label: 'EMS', apps: true }, { gtype: 'gang', name: 'lostmc', label: 'Lost MC' }] }],
      getMenu: [{ label: 'EMS', apps: true, funds: true, appsOpen: true, newApps: 2, balance: 284650, callsigns: true, gradeEdit: true, ownGrade: 5 }],
      getProfile: [{ hiredAt: '10-03-2026', probationUntil: '11-17-2026 20:00', hoursWeek: 6.5, lastCheckin: '11-14-2026 18:02', phone: '(555) 014-2290', email: 'jane.doe@ems.ls',
        commendations: 2, warnings: 0, contracts: [{ id: 42, number: 'EA-0042', at: '10-03-2026' }],
        records: [{ type: 'commend', text: 'Stayed late to cover the Paleto call.', by_name: 'Dr. Steven Blaze', at: '11-09-2026' }, { type: 'commend', text: 'Great teamwork at the highway pile-up.', by_name: 'Dr. Steven Blaze', at: '10-28-2026' }] }],
      getPayroll: [{ grades: [{ name: 'Chief', pay: 1000, members: 1, onduty: 1 }, { name: 'Senior Paramedic', pay: 700, members: 1, onduty: 0 }, { name: 'Paramedic', pay: 550, members: 2, onduty: 1 }, { name: 'EMT', pay: 400, members: 1, onduty: 1 }], perPaycheckAll: 3200, perPaycheckOnDuty: 1950 }],
      getStaff: [{ members: staffList, limit: 5, grades: grades }],
      getAnnouncement: [{ message: 'Training night Thursday 8pm at Pillbox. Bring your trauma kit.', by_name: 'Dr. Steven Blaze', at: '11-13-2026 18:00' }],
      getApplications: [[{ id: 1, name: 'Sam Rivers', status: 'new', created: '11-14-2026 18:20' }, { id: 2, name: 'Leah Tran', status: 'interview', created: '11-13-2026 21:02' }]],
      getApplication: [{ id: 1, name: 'Sam Rivers', status: 'new', statusLabel: 'New', votes: { up: 2, down: 0, mine: 0 },
        answers: [{ label: 'Why do you want to join EMS?', answer: 'I volunteered with a first-aid team for two years.' }, { label: 'Available evenings', type: 'checkbox', answer: true }] }],
      getFunds: [{ balance: 284650, left: 7500, confirmAbove: 5000, history: [{ name: 'Jane Doe', type: 'deposit', amount: 2500, reason: 'Fundraiser', at: '11-14-2026 19:02' }, { name: 'Dr. Steven Blaze', type: 'withdraw', amount: 800, reason: 'Medical supplies', at: '11-13-2026 16:40' }] }],
      getAudit: [[{ actor: 'Dr. Steven Blaze', event: 'hire', message: 'Hired Jane Doe as Probationary EMT', at: '11-12-2026 20:15' }, { actor: 'Jane Doe', event: 'deposit', message: 'Deposited $2,500 (Fundraiser)', at: '11-14-2026 19:02' }]],
    };
    return {
      call: function (name) { return Promise.resolve(D[name] || [true, 'Done (demo).']); },
      notify: function () {},
    };
  }

  // ---------------------------------------------------------------- start
  function layout() { document.getElementById('app').classList.toggle('narrow', window.innerWidth < 640); }
  function start() {
    api = makeApi();
    NATIVE = DEVICE === 'phone' && typeof window.SetPopUp === 'function' ? 'phone'
      : (DEVICE === 'computer' && window.computer && window.computer.inComputer !== false && window.parent !== window && window.computer.dialog) ? 'computer' : false;
    if (api.theme) document.documentElement.setAttribute('data-theme', api.theme);
    document.body.classList.remove('phone-wait');
    document.body.style.visibility = 'visible';
    layout();
    window.addEventListener('resize', layout);
    refresh();
  }

  if (DEVICE === 'phone') {
    // sd-phone puts its API into the page, then says "componentsLoaded". In a normal browser: demo data.
    if (!window.invokeNative) start();
    else window.addEventListener('message', function (e) { if (e.data === 'componentsLoaded' && !api) start(); });
  } else if (window.parent === window) {
    start(); // a normal browser tab: demo data
  } else if (window.computer && window.computer.isReady) {
    start();
  } else {
    window.addEventListener('computer:ready', function () { if (!api) start(); }, { once: true });
  }
})();
