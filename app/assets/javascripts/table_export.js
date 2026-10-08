// Download any table as PDF, CSV or Excel (2026-10-08). A small "Download"
// menu goes above every data table (Bootstrap .table, .basic-table, or a
// DataTable, or any table with headings) with at least one row. It sends what the table shows, after the
// page's own filters, to TableExportsController, which makes the file.
//   data-no-export      on a table (or around it): no menu
//   data-export-title   / data-export-subtitle: name the file and the PDF
// Columns with no heading and no text (tick boxes, edit icons) are left out.
(function () {
  var SELECTOR = 'table';
  var ACTIONS = /^(view|edit|delete|remove|show|open|details|select|cancel)$/i;

  function clean(s) {
    return (s || '').replace(/ /g, ' ').split('\n')
      .map(function (l) { return l.replace(/\s+/g, ' ').trim(); })
      .filter(function (l) { return l.length; }).join('\n');
  }

  function cellText(cell) {
    var copy = cell.cloneNode(true);
    $(copy).find('input, select, button, .no-export, script, style').remove();
    // plain action links (View, Edit, Delete) aren't data
    $(copy).find('a').filter(function () { return ACTIONS.test($(this).text().trim()); }).remove();
    // innerText keeps line breaks, but only on attached nodes
    var holder = document.createElement('div');
    holder.style.position = 'absolute'; holder.style.left = '-99999px';
    holder.appendChild(copy); document.body.appendChild(holder);
    var t = copy.innerText; document.body.removeChild(holder);
    return clean(t);
  }

  function bodyRows(table) {
    if ($.fn.dataTable && $.fn.dataTable.isDataTable && $.fn.dataTable.isDataTable(table)) {
      return $(table).DataTable().rows({ search: 'applied' }).nodes().toArray();
    }
    return $(table).children('tbody').children('tr').filter(function () {
      return this.style.display !== 'none' && !$(this).hasClass('no-export');
    }).toArray();
  }

  function heading(table) {
    var t = $(table).data('export-title');
    if (t) return t;
    // headings without their buttons ("Garages" not "Garages Add a garage")
    var bare = function (el) { if (!el) return ''; var c = el.cloneNode(true); $(c).find('a, button, .btn, small, .badge, .label').remove(); return c.textContent; };
    var panel = bare($(table).closest('.panel').find('> .panel-heading').get(0));
    var page = bare($('h1:visible, .page-header h2:visible, h2:visible').get(0));
    var parts = [clean(page), clean(panel)].filter(function (x) { return x; });
    return parts.join(': ').replace(/\n/g, ' ') || document.title;
  }

  function collect(table) {
    var heads = $(table).children('thead').find('tr').last().children('th, td').toArray().map(cellText);
    var rows = bodyRows(table).map(function (tr) {
      return $(tr).children('td, th').toArray().map(cellText);
    }).filter(function (r) { return r.some(function (c) { return c; }); });
    // a column with no heading is kept only if it says different things
    // per row: tick boxes and View / Edit links are left out
    // and a column that's empty in every row (a form field) says nothing
    var keep = heads.map(function (h, i) {
      var seen = {};
      rows.forEach(function (r) { if (r[i]) seen[r[i]] = 1; });
      var n = Object.keys(seen).length;
      return h ? n > 0 : n > 1;
    });
    return {
      title: heading(table),
      subtitle: $(table).data('export-subtitle') || '',
      columns: heads.filter(function (h, i) { return keep[i]; }).map(function (h, i) { return h || ('Column ' + (i + 1)); }),
      rows: rows.map(function (r) { return r.filter(function (c, i) { return keep[i]; }); }),
      page_only: $(table).nextAll('.pagination, div.pagination').length > 0 || $(table).parent().nextAll('.pagination, div.pagination').length > 0
    };
  }

  function send(table, format) {
    // same window: the reply is an attachment, so the page stays put
    var form = $('<form method="post" style="display:none">').attr('action', '/table_exports');
    form.append($('<input type="hidden" name="authenticity_token">').val($('meta[name=csrf-token]').attr('content')));
    form.append($('<input type="hidden" name="export_format">').val(format));
    form.append($('<input type="hidden" name="table">').val(JSON.stringify(collect(table))));
    $('body').append(form); form.submit(); form.remove();
  }

  function attach(table) {
    if (table.getAttribute('data-export-ready') || $(table).closest('[data-no-export]').length) return;
    if (!$(table).is('[data-export]')) {
      // not layout tables, pickers, or tables inside forms, dialogs or other tables
      if ($(table).parents('table, .modal, form, .dataTables_scrollBody, .ui-datepicker, .wc-container, .popover').length) return;
      // no heading text, no data table (the Dispatch run list draws its own)
      if (!$(table).children('thead').find('th').toArray().some(function (th) { return clean(th.textContent); })) return;
    }
    if (bodyRows(table).length < 1) return;
    table.setAttribute('data-export-ready', '1');
    var bar = $('<div class="tx-bar"><div class="btn-group">' +
      '<button type="button" class="btn btn-default btn-xs dropdown-toggle tx-btn" data-toggle="dropdown">' +
      '<i class="fa fa-download"></i> Download <span class="caret"></span></button>' +
      '<ul class="dropdown-menu dropdown-menu-right">' +
      '<li><a href="#" data-f="pdf"><i class="fa fa-file-pdf-o"></i> PDF</a></li>' +
      '<li><a href="#" data-f="xlsx"><i class="fa fa-file-excel-o"></i> Excel</a></li>' +
      '<li><a href="#" data-f="csv"><i class="fa fa-file-text-o"></i> CSV</a></li></ul></div></div>');
    bar.on('click', 'a[data-f]', function (e) { e.preventDefault(); send(table, $(this).data('f')); });
    var anchor = $(table).closest('.dataTables_wrapper');
    (anchor.length ? anchor : $(table)).before(bar);
  }

  function scan() { $(SELECTOR).each(function () { attach(this); }); }

  if (!document.getElementById('tx-style')) {
    $('head').append('<style id="tx-style">' +
      '.tx-bar { text-align: right; margin: 0 0 4px; }' +
      '.tx-bar .tx-btn { color: #12264F; border-color: #12264F; font-weight: 600; }' +
      '.tx-bar .tx-btn:hover, .tx-bar .open .tx-btn { background: #12264F; color: #fff; }' +
      '@media print { .tx-bar { display: none; } }</style>');
  }
  $(scan);
  // tables that arrive later (ajax lists, DataTables drawing)
  var pending = null;
  new MutationObserver(function () {
    clearTimeout(pending); pending = setTimeout(scan, 400);
  }).observe(document.documentElement, { childList: true, subtree: true });
  window.TableExport = { scan: scan, collect: collect };
})();
