require "tmpdir"

# Footer version: the date (Central) and commit of the code that is running, read
# from git at boot, e.g. "2026.10.04 (6f8a1145)". Edits only reach staff after
# `docker restart ridepilot_app_1`, which re-runs this, so it matches what they see.
# Falls back to the last CamSys release number if git can't be read.
version = begin
  Dir.mktmpdir do |home|
    # the container's git (2.30) refuses a repo owned by another user unless a
    # config FILE marks it safe; -c safe.directory on the command line is ignored
    File.write(File.join(home, ".gitconfig"), "[safe]\n\tdirectory = #{Rails.root}\n")
    IO.popen({ "HOME" => home, "TZ" => "America/Chicago" },
             ["git", "-C", Rails.root.to_s, "log", "-1", "--date=format-local:%Y.%m.%d", "--format=%cd (%h)"],
             err: File::NULL, &:read).to_s.strip.presence
  end
rescue SystemCallError
  nil
end
Ridepilot::Application.config.version = version || "2.1.12"
