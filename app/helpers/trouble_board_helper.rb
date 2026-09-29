# Charts for the trouble board, drawn as inline SVG (no chart library).
module TroubleBoardHelper
  # a small trend line with a soft fill; flat and faint when there's nothing
  def tb_sparkline(values, color, width: 120, height: 32)
    values = Array(values)
    return "".html_safe if values.size < 2
    max = [values.max.to_f, 1].max
    step = (width - 4).to_f / (values.size - 1)
    points = values.each_with_index.map { |v, i| [2 + i * step, height - 3 - (v / max) * (height - 8)] }
    line = points.map { |x, y| "#{x.round(1)},#{y.round(1)}" }.join(" ")
    area = "2,#{height - 3} #{line} #{(2 + (values.size - 1) * step).round(1)},#{height - 3}"
    last_x, last_y = points.last
    quiet = values.sum.zero?
    content_tag(:svg, viewBox: "0 0 #{width} #{height}", width: width, height: height, class: "tb-spark", "aria-hidden": true) do
      safe_join([
        tag.polygon(points: area, fill: color, "fill-opacity": quiet ? 0 : 0.14),
        tag.polyline(points: line, fill: "none", stroke: quiet ? "#cfd6df" : color, "stroke-width": 1.8, "stroke-linejoin": "round", "stroke-linecap": "round"),
        (tag.circle(cx: last_x.round(1), cy: last_y.round(1), r: 2.6, fill: color) unless quiet)
      ].compact)
    end
  end

  # stacked bars, one per day, one colour per kind
  def tb_daily_bars(board)
    kinds = TroubleBoard::KINDS
    dates = board.dates
    totals = dates.each_index.map { |i| kinds.keys.sum { |k| board.summary[k][:daily][i] } }
    max = tb_nice_max(totals.max.to_i)
    w, h, left, bottom, top = 820, 210, 34, 24, 8   # near the drawn size on a laptop, so labels stay readable
    plot_w, plot_h = w - left - 6, h - bottom - top
    slot = plot_w.to_f / dates.size
    bar_w = [[slot * 0.68, 2].max, 34].min
    label_every = { 7 => 1, 30 => 5, 90 => 15 }[board.days] || 1
    parts = []
    [0, max / 2.0, max].uniq.each do |v|
      y = (top + plot_h - v / max.to_f * plot_h).round(1)
      parts << tag.line(x1: left, x2: w - 6, y1: y, y2: y, class: "tb-grid-line")
      parts << tag.text(v % 1 == 0 ? v.to_i : v, x: left - 6, y: y + 4, class: "tb-axis", "text-anchor": "end")
    end
    dates.each_with_index do |date, i|
      x = left + i * slot + (slot - bar_w) / 2
      y = top + plot_h
      breakdown = kinds.map { |k, meta| "#{meta[:label]}: #{board.summary[k][:daily][i]}" }.join(", ")
      bars = kinds.map do |k, meta|
        n = board.summary[k][:daily][i]
        next if n.zero?
        bh = n / max.to_f * plot_h
        y -= bh
        tag.rect(x: x.round(1), y: y.round(1), width: bar_w.round(1), height: bh.round(1), fill: meta[:color], rx: 1.5)
      end.compact
      parts << content_tag(:g) { safe_join([tag.title("#{date.strftime('%a %-m/%-d')}: #{breakdown}")] + bars + [tag.rect(x: (left + i * slot).round(1), y: top, width: slot.round(1), height: plot_h, fill: "transparent")]) }
      if (dates.size - 1 - i) % label_every == 0
        last = i == dates.size - 1   # the newest day's label hugs the right edge instead of running off it
        parts << tag.text(date.strftime("%-m/%-d"), x: (last ? w - 6 : left + i * slot + slot / 2).round(1), y: h - 6,
                          class: "tb-axis", "text-anchor": last ? "end" : "middle")
      end
    end
    content_tag(:svg, safe_join(parts), viewBox: "0 0 #{w} #{h}", class: "tb-bars", role: "img",
                "aria-label": "Trouble per day over the last #{board.days} days")
  end

  # "▲ 40% vs the 7 days before": up is bad (red), down is good (green)
  def tb_delta(current, previous, days)
    vs = "vs the #{days} days before"
    if current.zero? && previous.zero?
      content_tag(:span, "Nothing either period", class: "tb-delta tb-flat")
    elsif previous.zero?
      content_tag(:span, "None in the #{days} days before", class: "tb-delta tb-flat")
    else
      pct = ((current - previous) * 100.0 / previous).round
      if pct.zero?
        content_tag(:span, "Same as the #{days} days before", class: "tb-delta tb-flat")
      else
        content_tag(:span, "#{pct.positive? ? '▲' : '▼'} #{pct.abs}% #{vs}", class: "tb-delta #{pct.positive? ? 'tb-up' : 'tb-down'}")
      end
    end
  end

  def tb_ago(time)
    return "" unless time
    "#{time_ago_in_words(time.in_time_zone)} ago"
  end

  # "ActiveRecord::RecordNotFound: Couldn't find Trip" -> [class, message]
  def tb_split_error(detail)
    klass, message = detail.to_s.split(": ", 2)
    message ? [klass, message] : [nil, klass]
  end

  def tb_nice_max(n)
    return 4 if n <= 4
    magnitude = 10**(Math.log10(n).floor)
    [1, 2, 4, 6, 8, 10].map { |m| m * magnitude }.find { |c| c >= n }
  end
end
