require "rubyXL"
require "rubyXL/convenience_methods"

# A report's CSV as a branded Excel workbook (docs/design-language.md): the
# GCRPC masthead (organisation in Copperplate, report name in navy, a gold rule
# under it), the run time and parameters in muted small type, then each table
# with a navy head, hairline rules and soft zebra rows, in Open Sans on the
# print ladder (9 / 11 / 14.5 pt). Numbers stay numbers so Excel can total them.
#
# The CSV is the one every v2 report already renders (reports/_common_csv_header
# then the report's own rows), so any report with a CSV download gets this.
# rubyXL can't place images, so the seal is left to the PDF.
class ReportWorkbook
  ORG = "Golden Crescent Regional Planning Commission".freeze
  NAVY, GOLD, INK, MUTED, LINE, SOFT, WHITE = %w[12264F CC9900 131313 5F6B7A CFD6E4 F4F6FA FFFFFF].freeze
  TEXT_FONT = "Open Sans".freeze
  ORG_FONT = "Copperplate Gothic Bold".freeze
  MAX_WIDTH = 48

  def self.from_csv(csv, title:)
    new(CSV.parse(csv), title).build
  end

  def initialize(rows, title)
    @rows = rows.map { |r| r.map { |v| v.nil? ? nil : excel_value(v) } }
    @title = title.to_s
  end

  def build
    @book = RubyXL::Workbook.new
    @book.fonts[0].set_name(TEXT_FONT)   # the default, for every cell not styled below (rubyXL's is Verdana 10)
    @book.fonts[0].set_size(11)
    @sheet = @book[0]
    @sheet.sheet_name = @title.gsub(%r{[\\/?*\[\]:]}, ' ').first(31).presence || 'Report'
    @width = [@rows.map(&:size).max.to_i, 1].max

    masthead
    body = @rows.drop(1)                 # the CSV's first line is the report name, now in the masthead
    offset = 2
    in_table = false
    zebra = 0
    cols = 0
    @table_rows = []                     # what column widths are measured from
    body.each_with_index do |row, i|
      r = offset + i
      if header?(row, body[i + 1])
        row.each_with_index { |v, c| style(put(r, c, v), font: TEXT_FONT, size: 11, color: WHITE, bold: true, fill: NAVY, border: NAVY) }
        in_table, zebra, cols = true, 0, row.size
        @table_rows << row
      elsif row.compact.empty? || row.all? { |v| v.to_s.strip.empty? }
        in_table = false
      elsif in_table
        zebra += 1
        total = total_row?(row)
        @table_rows << row
        (0...[row.size, cols].max).each do |c|
          style(put(r, c, row[c]), font: TEXT_FONT, size: 11, color: INK, bold: total,
                fill: (zebra.even? ? SOFT : nil), border: LINE, money: row[c].is_a?(Float))
        end
      else                               # run time, parameters, summary lines above a table
        row.each_with_index do |v, c|
          style(put(r, c, v), font: TEXT_FONT, size: 11, color: (v.is_a?(Numeric) ? INK : MUTED),
                bold: c.zero? && !v.to_s.strip.empty?, money: v.is_a?(Float))
        end
      end
    end

    widths
    print_setup
    @book
  end

  # Printed from Excel: landscape, letter, every column on one page width
  # (as many pages tall as it takes), and the navy tab colour.
  def print_setup
    @sheet.sheet_pr ||= RubyXL::WorksheetProperties.new
    @sheet.sheet_pr.page_set_up_pr = RubyXL::PageSetupProperties.new(fit_to_page: true)
    @sheet.sheet_pr.tab_color = RubyXL::Color.new(rgb: "FF#{NAVY}")
    @sheet.page_setup = RubyXL::PageSetup.new(orientation: "landscape", paper_size: 1, fit_to_width: 1, fit_to_height: 0)
  end

  private

  def masthead
    style(put(0, 0, ORG), font: ORG_FONT, size: 14.5, color: NAVY, bold: true)
    style(put(1, 0, @rows.first&.first || @title), font: TEXT_FONT, size: 11, color: NAVY, bold: true)
    (0...@width).each do |c|             # the gold rule under the masthead, across the sheet
      cell = (@sheet[1] && @sheet[1][c]) || put(1, c, nil)
      cell.change_border(:bottom, 'medium')
      cell.change_border_color(:bottom, GOLD)
    end
    @sheet.change_row_height(0, 22)
  end

  # A table head: two or more cells, all words, with a row under it of the
  # same width that holds a number or more words (the first data row).
  def header?(row, nxt)
    cells = row.compact
    return false if cells.size < 2 || cells.any? { |v| v.is_a?(Numeric) } || cells.any? { |v| v.to_s.strip.empty? }
    return false unless nxt && nxt.compact.size >= 2
    nxt.size >= row.size - 1 && nxt.any? { |v| v.is_a?(Numeric) || v.to_s =~ /\d/ }
  end

  def total_row?(row)
    first = row.first.to_s
    first.match?(/\A(total|all agencies)\b/i) || first.match?(/ total\z/i)
  end

  def put(r, c, v)
    @sheet.add_cell(r, c, v)
  end

  def style(cell, font:, size:, color:, bold: false, fill: nil, border: nil, money: false)
    cell.change_font_name(font)
    cell.change_font_size(size)
    cell.change_font_color(color)
    cell.change_font_bold(true) if bold
    cell.change_fill(fill) if fill
    if border
      %i[top bottom left right].each { |side| cell.change_border(side, 'thin'); cell.change_border_color(side, border) }
    end
    cell.set_number_format('#,##0.00') if money
    cell
  end

  def widths
    (0...@width).each do |c|
      measured = @table_rows.presence || @rows.drop(1)
      longest = measured.map { |r| r[c].is_a?(Float) ? format('%.2f', r[c]).size : r[c].to_s.size }.max.to_i
      @sheet.change_column_width(c, [[longest + 2, 8].max, MAX_WIDTH].min)
    end
  end

  # "12" -> 12, "3.50" -> 3.5; anything else, including "007" and long ids, stays text
  def excel_value(text)
    return text.to_i if text.match?(/\A-?(?:0|[1-9]\d{0,14})\z/)
    return text.to_f if text.match?(/\A-?(?:0|[1-9]\d{0,14})\.\d+\z/)
    text
  end
end
