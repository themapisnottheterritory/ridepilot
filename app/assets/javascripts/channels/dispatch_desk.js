// The dispatch desk on every staff page (shared/_dispatch_desk): a pop-up and
// a chime when a driver writes, the header inbox count and list, a flashing
// tab title and a desktop notification when RidePilot isn't the tab in front,
// and emergency banners that sound until someone presses "Got it!".
// Plain ES5: the asset pipeline doesn't transpile.
(function () {
  var D, ctx, alarmTimer = null, titleTimer = null, baseTitle = document.title, unhandled = 0;

  function soundKey() { return 'dd-sound-' + D.userId; }
  function soundOn() { try { return localStorage.getItem(soundKey()) !== 'off'; } catch (e) { return true; } }

  function audio() {
    if (!ctx) { var A = window.AudioContext || window.webkitAudioContext; if (!A) return null; ctx = new A(); }
    if (ctx.state === 'suspended') ctx.resume();
    return ctx;
  }
  function tone(freq, start, len, vol, type) {
    var a = audio(); if (!a) return;
    var o = a.createOscillator(), g = a.createGain(), t = a.currentTime + start;
    o.type = type || 'sine'; o.frequency.value = freq;
    g.gain.setValueAtTime(0.0001, t); g.gain.exponentialRampToValueAtTime(vol, t + 0.02); g.gain.exponentialRampToValueAtTime(0.0001, t + len);
    o.connect(g); g.connect(a.destination); o.start(t); o.stop(t + len + 0.05);
  }
  function chime() { if (!soundOn()) return; tone(659, 0, 0.35, 0.18); tone(880, 0.18, 0.5, 0.15); }
  // emergencies sound even when the chime is muted
  function alarmBurst() { for (var i = 0; i < 3; i++) { tone(988, i * 0.32, 0.22, 0.35, 'square'); tone(740, i * 0.32 + 0.14, 0.16, 0.3, 'square'); } }

  // The Central-time date of a moment, "2026-10-02": pop-ups belong to one
  // dispatch day and go at Central midnight, whatever zone the PC is set to.
  function centralDay(d) { return (d || new Date()).toLocaleDateString('en-CA', { timeZone: 'America/Chicago' }); }
  function clearOldToasts() {
    var today = centralDay();
    $('#dd-toasts .dd-toast').each(function () { if ($(this).attr('data-day') !== today) $(this).remove(); });
  }

  function esc(s) { return $('<div>').text(s == null ? '' : String(s)).html(); }
  function clock(iso) { var d = iso ? new Date(iso) : new Date(); return d.toLocaleTimeString([], { hour: 'numeric', minute: '2-digit' }); }

  function openChat(runId) {
    if (!runId) return;
    window.open(D.chatUrl.replace('RUN', runId), 'chat_' + runId, 'width=800, height=600');
  }

  // ---- header count and tab title ----
  function setCount(n) {
    unhandled = Math.max(0, n | 0);
    var link = $('#dispatch-inbox-link'), badge = link.find('.dd-count');
    if (unhandled > 0) {
      if (!badge.length) badge = $('<span class="dd-count"></span>').appendTo(link);
      badge.text(unhandled);
      link.attr('title', 'Messages from drivers (' + unhandled + ' not yet seen)');
    } else { badge.remove(); link.attr('title', 'Messages from drivers'); }
    flashTitle();
  }
  function flashTitle() {
    clearInterval(titleTimer); titleTimer = null; document.title = baseTitle;
    if (!document.hidden || unhandled === 0) return;
    var on = false;
    titleTimer = setInterval(function () { on = !on; document.title = on ? '(' + unhandled + ') Driver message' : baseTitle; }, 1000);
  }

  // ---- pop-ups ----
  function toast(m) {
    var box = $('#dd-toasts');
    box.find('.dd-toast[data-driver-id="' + m.driver_id + '"]').remove();   // one per driver: the latest
    var t = $('<div class="dd-toast"></div>').attr('data-driver-id', m.driver_id).attr('data-day', centralDay(m.at ? new Date(m.at) : new Date())).html(
      '<div class="dd-top"><b class="dd-who">' + esc(m.driver_name) + '</b>' + (m.run_name ? '<span class="dd-run">' + esc(m.run_name) + '</span>' : '') +
      '<span class="dd-time">' + clock(m.at) + '</span></div><div class="dd-body">' + esc(m.body) + '</div>' +
      '<div class="dd-actions"><button class="dd-btn primary dd-reply">Reply</button><button class="dd-btn quiet dd-close">Dismiss</button></div>');
    t.find('.dd-reply').on('click', function () { openChat(m.run_id); t.remove(); });
    t.find('.dd-close').on('click', function () { t.remove(); });
    box.prepend(t);
    while (box.children().length > 4) box.children().last().remove();
  }

  function desktop(m) {
    if (!document.hidden || !('Notification' in window) || Notification.permission !== 'granted') return;
    var n = new Notification(m.driver_name + (m.run_name ? ' (' + m.run_name + ')' : ''), { body: m.body, tag: 'dd-driver-' + m.driver_id });
    n.onclick = function () { window.focus(); openChat(m.run_id); n.close(); };
  }

  // ---- inbox list ----
  function footer() {
    $('#dd-sound').text(soundOn() ? 'Sound: on (turn off)' : 'Sound: off (turn on)');
    var d = $('#dd-desktop');
    if (!('Notification' in window)) d.hide();
    else if (Notification.permission === 'granted') d.text('Desktop alerts: on').css('cursor', 'default');
    else if (Notification.permission === 'denied') d.text('Desktop alerts: blocked in the browser');
    else d.text('Turn on desktop alerts');
  }
  function togglePanel(e) {
    e.preventDefault();
    var p = $('#dd-panel');
    if (p.is(':visible')) { p.hide(); return; }
    var r = this.getBoundingClientRect();
    p.css({ top: r.bottom + 10, left: Math.max(12, Math.min(r.right - 380, window.innerWidth - 392)) }).show();
    footer();
    p.find('.dd-list').html('<div class="dd-empty" style="color:#5f6b7a">Loading…</div>').load(D.inboxUrl);
  }

  // ---- emergencies ----
  function showEmergency(id, message, at) {
    if ($('#dd-em-' + id).length) return;
    var b = $('<div class="dd-emergency"></div>').attr('id', 'dd-em-' + id).html(
      '<i class="fa fa-exclamation-triangle"></i><span class="dd-em-text">' + esc(message) +
      ' <span class="dd-em-time">' + clock(at) + '</span></span><button>Got it!</button>');
    b.find('button').on('click', function () {
      if (App.alerts && App.alerts[D.providerId]) App.alerts[D.providerId].dismiss(id, D.userId);
      dropEmergency(id);
    });
    $('#dd-emergencies').append(b);
    alarmBurst();
    if (!alarmTimer) alarmTimer = setInterval(function () { if ($('.dd-emergency').length) alarmBurst(); else { clearInterval(alarmTimer); alarmTimer = null; } }, 4000);
    if (document.hidden && 'Notification' in window && Notification.permission === 'granted') {
      new Notification('EMERGENCY', { body: message, tag: 'dd-em-' + id, requireInteraction: true });
    }
  }
  function dropEmergency(id) { $('#dd-em-' + id).remove(); }
  window.DispatchDeskEmergency = { show: showEmergency, drop: dropEmergency };

  $(function () {
    D = window.DispatchDesk;
    if (!D || !window.App || !App.cable) return;

    setCount(parseInt($('#dispatch-inbox-link .dd-count').text(), 10) || 0);
    $(document).on('click', '#dispatch-inbox-link', togglePanel);
    $(document).on('click', '#dd-panel .dd-row', function (e) { e.preventDefault(); openChat($(this).data('run-id')); $('#dd-panel').hide(); });
    $(document).on('click', function (e) { if (!$(e.target).closest('#dd-panel, #dispatch-inbox-link').length) $('#dd-panel').hide(); });
    $('#dd-sound').on('click', function () {
      try { localStorage.setItem(soundKey(), soundOn() ? 'off' : 'on'); } catch (e) {}
      footer(); if (soundOn()) chime();
    });
    $('#dd-desktop').on('click', function () {
      if ('Notification' in window && Notification.permission === 'default') Notification.requestPermission().then(footer);
    });
    // browsers only allow sound after the person has clicked something on the page
    $(document).one('click keydown', function () { audio(); });
    document.addEventListener('visibilitychange', flashTitle);
    // yesterday's pop-ups go at Central midnight (and when someone comes back to the tab)
    setInterval(clearOldToasts, 60 * 1000);
    document.addEventListener('visibilitychange', function () { if (!document.hidden) clearOldToasts(); });

    (D.openEmergencies || []).forEach(function (a) { showEmergency(a.id, a.message, a.at); });

    App.dispatchDesk = App.cable.subscriptions.create({ channel: 'DispatchChannel', provider_id: D.providerId }, {
      received: function (m) {
        if (m.kind === 'chat') {
          setCount(m.unhandled); toast(m); chime(); desktop(m);
        } else if (m.kind === 'handled') {
          setCount(m.unhandled);
          $('#dd-toasts .dd-toast[data-driver-id="' + m.driver_id + '"]').remove();
          if ($('#dd-panel').is(':visible')) $('#dd-panel .dd-list').load(D.inboxUrl);
        }
      }
    });
  });
})();
