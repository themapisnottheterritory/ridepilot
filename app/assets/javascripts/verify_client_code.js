// function to check if need to verify code
function check_if_verify_client_code(url, callback_fn) {
  $.ajax({
    url: url,
    success: function(data) {
      callback_fn(data);
    }
  });
}


// prompt dialog to verify customer code
function verify_client_code(code, code_verify_url, callback_fn, abort_fn) {
  bootbox.confirm({
    message: 'The customer code is: <b>' + code + '</b>. Please confirm.', 
    buttons: {
        confirm: {
            label: 'Confirm'
        },
        cancel: {
            label: 'Abort'
        }
    }, 
    callback: function(result) {
      if(result) {
        // flag as confirmed
        $.ajax({
          url: code_verify_url,
          type: 'POST'
        }).done(function() {
          //proceed callback
          if(callback_fn) {
            callback_fn();
          }
        });
      } else {
        if(abort_fn) {
          abort_fn();
        }
      }
    }
  });
}
// A Save that stops at a question (customer code Abort, AM/PM "Change it",
// past date, run disruption, possible double booking) left the Save button
// greyed out until the page was reloaded: jquery_ujs disables data-disable-with
// buttons as the form starts to submit, and only a page load enabled them again
// (2026-10-06). A confirm answered Abort/Cancel/No, or the double-booking
// dialog closed without Continue, now gives the form's buttons back.
(function() {
  function giveSaveBack() {
    if (!$.rails || !$.rails.enableFormElements) return;
    $('form').each(function() {
      if ($(this).find('[data-disable-with]:disabled').length) $.rails.enableFormElements($(this));
    });
  }

  if (window.bootbox && bootbox.confirm) {
    var confirm = bootbox.confirm;
    bootbox.confirm = function() {
      var args = Array.prototype.slice.call(arguments);
      var wrap = function(cb) {
        return function(result) {
          var r = cb ? cb.apply(this, arguments) : undefined;
          if (!result) giveSaveBack();
          return r;   // a callback returning false keeps the dialog open
        };
      };
      if (args[0] && typeof args[0] === 'object') {
        args[0] = $.extend({}, args[0], { callback: wrap(args[0].callback) });
      } else if (typeof args[args.length - 1] === 'function') {
        args[args.length - 1] = wrap(args[args.length - 1]);
      }
      return confirm.apply(bootbox, args);
    };
  }

  $(document).on('click', '.submit-double-book-modal', function() {
    $(this).closest('.modal').data('continued', true);
  });
  $(document).on('hidden.bs.modal', '#doubleBookedTripDialog', function() {
    if (!$(this).data('continued')) giveSaveBack();
    $(this).data('continued', false);
  });
})();
