// AM/PM guard for the trip and subscription forms (form.trip_form).
// Times like 12:00 AM or 3:45 AM were being saved where PM was meant: on
// 2026-10-05 four subscriptions had 30 upcoming trips at midnight or 3:45 AM.
// Before the form's own save handlers run, ask about any pickup or appointment
// time between 12:00 AM and 4:59 AM. "Keep" saves as entered; "Change it" goes
// back to the form. One question per save.
//
// It listens for the CLICK on the form's submit button (capture phase), not the
// submit event: these forms catch the click and save through jQuery, which never
// fires a native submit event. The time fields are hidden inputs filled by the
// time widget (hour, minute, AM/PM buttons).
(function () {
  function early(value) {
    var m = /^\s*(\d{1,2}):(\d{2})\s*([AaPp])[Mm]\s*$/.exec(value || "");
    if (!m || m[3].toUpperCase() !== "A") return null;
    var h = parseInt(m[1], 10);
    if (h === 12 || h < 5) return { text: m[1] + ":" + m[2] + " AM", pm: m[1] + ":" + m[2] + " PM" };
    return null;
  }

  document.addEventListener("click", function (e) {
    var button = e.target.closest && e.target.closest('[type="submit"]');
    var form = button && button.form;
    if (!form || !form.classList.contains("trip_form")) return;
    if (button.dataset.ampmOk === "1") { delete button.dataset.ampmOk; return; }
    if (typeof bootbox === "undefined") return;

    var fields = form.querySelectorAll('input[id$="_pickup_time"], input[id$="_appointment_time"]');
    var hit = null;
    for (var i = 0; i < fields.length && !hit; i++) {
      var t = early(fields[i].value);
      if (t) hit = { field: fields[i], t: t };
    }
    if (!hit) return;

    e.preventDefault();
    e.stopPropagation();   // keep the form's own save handlers from running yet
    var what = /appointment/.test(hit.field.id) ? "appointment time" : "pickup time";
    var night = hit.t.text.indexOf("12:") === 0 ? " (midnight)" : "";
    bootbox.confirm({
      message: "The " + what + " is <b>" + hit.t.text + "</b>" + night + ". Did you mean <b>" + hit.t.pm + "</b>?",
      buttons: {
        confirm: { label: "Keep " + hit.t.text, className: "btn-default" },
        cancel: { label: "Change it", className: "btn-primary" }
      },
      callback: function (keep) {
        if (keep) {
          button.dataset.ampmOk = "1";
          setTimeout(function () { button.click(); }, 0);   // carry on with the normal save
        }
      }
    });
  }, true);
})();
