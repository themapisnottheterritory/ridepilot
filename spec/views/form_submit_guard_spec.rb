require "rails_helper"

# A bare $('form').submit() submits every form on the page, and the browser
# follows the first: for people in more than one agency that is the agency
# switcher in the header, so the page's own form is never sent (the Goliad
# agency page "does not stay", 2026-10-06). Name the form instead.
RSpec.describe "Page scripts" do
  it "never submit a bare $('form')" do
    bare = /\$\(\s*["']form["']\s*\)\s*\.(submit|trigger\(\s*["']submit)/
    files = Dir[Rails.root.join("app/views/**/*.{haml,erb}").to_s] + Dir[Rails.root.join("app/assets/javascripts/**/*.{js,coffee}").to_s]
    offenders = files.select { |f| File.read(f) =~ bare }.map { |f| f.delete_prefix("#{Rails.root}/") }
    expect(offenders).to be_empty
  end
end
