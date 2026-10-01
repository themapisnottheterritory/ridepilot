require "rails_helper"

RSpec.describe ReportWorkbook do
  let(:csv) do
    <<~CSV
      Fares Collected
      Report Datetime,10/01/2026 12:20 PM
      Parameters
      ,Date Range,10/01/2026 - 10/01/2026

      Agency,Collected,Run,Amount,Trip
      Victoria Transit GCRPC,10/01/2026 08:12,RGON2,2.00,2457
      Goliad County,10/01/2026 09:03,Rgol1,3.50,0201
    CSV
  end
  let(:bytes) { described_class.from_csv(csv, title: "Fares Collected").stream.read }
  let(:sheet) { RubyXL::Parser.parse_buffer(bytes)[0] }
  def cell(r, c) = sheet[r] && sheet[r][c]

  it "puts the GCRPC masthead on top: organisation, then the report name over a gold rule" do
    expect(cell(0, 0).value).to eq ReportWorkbook::ORG
    expect(cell(0, 0).font_name).to eq "Copperplate Gothic Bold"
    expect(cell(1, 0).value).to eq "Fares Collected"
    expect(cell(1, 0).get_border_color(:bottom)).to end_with ReportWorkbook::GOLD
  end

  it "gives the table a navy head with white text and keeps amounts as numbers" do
    head = (0..sheet.sheet_data.rows.size).find { |r| cell(r, 0)&.value == "Agency" }
    expect(cell(head, 0).fill_color).to end_with ReportWorkbook::NAVY
    expect(cell(head, 0).font_color).to end_with ReportWorkbook::WHITE
    expect(cell(head + 1, 3).value).to eq 2.0
    expect(cell(head + 2, 3).value).to eq 3.5
    expect(cell(head + 2, 4).value).to eq "0201"          # a leading zero stays text
  end

  it "writes a plain zip that LibreOffice and older Excel can open (no ZIP64)" do
    # ZIP64 entries need version 4.5 (45) to extract; a plain zip needs 2.0 (20)
    expect(bytes[4, 2].unpack1("v")).to eq 20
  end
end
