# The morning address check (rake addresses:scan): what AddressScan found that
# wasn't there the day before. To GCRPC I.T. (TroubleWatch::IT_EMAILS).
class AddressScanMailer < ActionMailer::Base
  default from: ENV["SYSTEM_SEND_FROM_ADDRESS"]

  def new_findings(findings, total, first_run: false)
    @findings = findings.group_by(&:kind)
    @total = total
    @first_run = first_run
    @providers = Provider.pluck(:id, :name).to_h
    @page = Rails.application.routes.url_helpers.address_checks_url(**ActionMailer::Base.default_url_options, locale: :en)
    mail(to: TroubleWatch::IT_EMAILS,
         subject: "[RidePilot] Address check: #{findings.size} #{first_run ? 'to fix (starting list)' : 'new'}")
  end
end
