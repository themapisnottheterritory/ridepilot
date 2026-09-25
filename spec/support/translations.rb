# The app reads its UI strings, button labels and validation messages from the
# translation tables (TranslationKey / Translation / Locale). The test database
# does not carry them, so seed them once per suite from spec/fixtures/
# translations.csv, an export of the live tables (locale,key,value). Refresh it
# with:
#   psql ridepilot -Atc "copy (select l.name, k.name, t.value from translations t
#     join translation_keys k on k.id=t.translation_key_id
#     join locales l on l.id=t.locale_id order by 1,2) to stdout with csv header"
require "csv"
module TestTranslations
  FIXTURE = Rails.root.join("spec", "fixtures", "translations.csv")

  def self.seed
    locales = Hash.new { |h, name| h[name] = Locale.find_or_create_by!(name: name) }
    keys = TranslationKey.pluck(:name, :id).to_h
    existing = Translation.pluck(:translation_key_id, :locale_id).to_set
    rows = []
    CSV.foreach(FIXTURE, headers: true) do |row|
      locale = locales[row["locale"]]
      key_id = keys[row["key"]] ||= TranslationKey.create!(name: row["key"]).id
      next if existing.include?([key_id, locale.id])
      rows << { translation_key_id: key_id, locale_id: locale.id, value: row["value"].to_s, created_at: Time.current, updated_at: Time.current }
    end
    # insert_all is refused by the PostGIS adapter; the rows are new, so plain inserts.
    Translation.transaction { rows.each { |r| Translation.create!(r) } }
  end
end
