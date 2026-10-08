require "csv"

# Download any table as PDF, CSV or Excel (2026-10-08, Phil: "if there is data
# in a tabular form we should make it available for a pdf or csv or excel").
# table_export.js puts a Download menu above each data table and posts what
# the table shows (headings and rows, after the page's own filters); this
# turns it into the file. It reads nothing from the database, so a user can
# only download what they could already see.
class TableExportsController < ApplicationController
  FORMATS = %w[pdf csv xlsx].freeze
  MAX_ROWS = 20_000
  NUMBER = /\A-?\$?\d{1,3}(,\d{3})*(\.\d+)?\z|\A-?\$?\d+(\.\d+)?\z/

  def create
    fmt = params[:export_format].to_s
    return head(:unprocessable_entity) unless FORMATS.include?(fmt)
    data = JSON.parse(params[:table].to_s) rescue nil
    return head(:unprocessable_entity) unless data.is_a?(Hash) && data["columns"].is_a?(Array)

    @title = data["title"].to_s.strip.presence || "RidePilot table"
    @subtitle = data["subtitle"].to_s.strip.presence
    @columns = data["columns"].map(&:to_s)
    @rows = Array(data["rows"]).first(MAX_ROWS).map { |r| Array(r).map(&:to_s).first(@columns.size) }
    @page_only = data["page_only"].present?
    name = "#{@title.parameterize.presence || 'table'}-#{Time.current.strftime('%Y%m%d')}"

    case fmt
    when "csv"
      csv = CSV.generate { |out| out << @columns; @rows.each { |r| out << r } }
      send_data "﻿#{csv}", filename: "#{name}.csv", type: "text/csv; charset=utf-8"   # BOM: Excel reads UTF-8
    when "xlsx"
      send_data xlsx, filename: "#{name}.xlsx", type: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
    when "pdf"
      @exported_by = current_user.try(:name).presence || current_user.try(:username)
      render pdf: name, template: "table_exports/sheet", formats: [:html], layout: false,
             disposition: "attachment", page_size: "Letter", encoding: "UTF-8",
             orientation: @columns.size > 6 ? "Landscape" : "Portrait",
             margin: { top: 11, bottom: 13, left: 10, right: 10 },
             footer: { right: "Page [page] of [topage]", font_size: 7, font_name: "DejaVu Sans" }
    end
  end

  private

  # Row 1 is the headings (navy, frozen, with filters), so the sheet sorts and
  # pivots as is. Money and plain numbers become numbers; everything else
  # stays as the page showed it.
  def xlsx
    pkg = Axlsx::Package.new
    pkg.workbook.add_worksheet(name: @title.gsub(%r{[\[\]*?/\\:]}, " ").first(31)) do |sheet|
      head = sheet.styles.add_style(b: true, fg_color: "FFFFFF", bg_color: "12264F", alignment: { vertical: :center, wrap_text: true })
      money = sheet.styles.add_style(num_fmt: 7)    # $#,##0.00
      plain = sheet.styles.add_style(alignment: { vertical: :top, wrap_text: false })
      sheet.add_row @columns, style: head, height: 22
      @rows.each do |row|
        values = row.map { |v| number(v) }
        styles = row.map { |v| v.start_with?("$", "-$") && number(v).is_a?(Numeric) ? money : plain }
        sheet.add_row values, style: styles, types: values.map { |v| v.is_a?(Numeric) ? nil : :string }
      end
      widths = @columns.each_index.map { |i| ([@columns[i].size] + @rows.first(500).map { |r| r[i].to_s.size }).max.clamp(6, 50) + 2 }
      sheet.column_widths(*widths)
      sheet.sheet_view.pane { |p| p.top_left_cell = "A2"; p.state = :frozen; p.y_split = 1 }
      sheet.auto_filter = "A1:#{Axlsx.cell_r(@columns.size - 1, [@rows.size, 1].max)}" if @columns.any?
    end
    pkg.to_stream.read
  end

  def number(v)
    s = v.to_s.strip
    return v unless s.match?(NUMBER) && !s.match?(/\A0\d/)   # keep zip codes, ids with leading zeros as text
    n = s.delete("$,")
    n.include?(".") ? n.to_f : n.to_i
  end
end
