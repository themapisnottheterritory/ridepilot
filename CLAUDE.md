# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Commands
- Install dependencies: `bundle install`
- Run server: `bundle exec rails server`
- Run console: `bundle exec rails console`
- Run all tests: `bundle exec rspec`
- Run single test: `bundle exec rspec spec/path/to/file_spec.rb:42`
- Database setup: `rails db:create db:migrate`
- Database reset: `rails db:reset`
- Test database setup: `RAILS_ENV=test rails db:test:prepare`
- With Docker: `docker-compose build && docker-compose up`

## Code Style Guidelines
- Ruby/Rails: Ruby 2.7.8, Rails 5.2.1
- Indentation: 2 spaces
- Classes: CamelCase, methods/variables: snake_case
- Models: associations → validations → callbacks → scopes → methods
- Controllers: use strong parameters, transactions for data integrity
- Views: HAML templates
- Testing: RSpec with Factory Bot, contextualized test scenarios
- Authentication: Devise + CanCanCan
- Error handling: ActiveRecord validations, rescue blocks, flash messages
- Provider scoping: Most models have provider association

## What's new (required for user-facing changes)
- Any change staff will notice (new feature, changed screen or behaviour, fixed bug they hit) gets a note at the TOP of `config/whats_new.yml` in the SAME commit. The header megaphone counts unread notes; Ask RidePilot reads the last 90 days of them.
- Write for a dispatcher, not a developer: what changed, where to find it, what to do differently; one to three short sentences; on-screen names in **bold**, exactly as they appear (check the view or translation). No commit hashes, class names or jargon.
- `added:` is when it goes live ("YYYY-MM-DD HH:MM" Central). Use `for: admins` for admin-only screens and `providers: [1]` for GCRPC-only things such as fixed route (107 Goliad, 143 Lavaca).
- Tag which app changed with `apps:` — `web` (RidePilot web, the default), `tablet` (driver tablet, GCRPC Demand Response), `fixed` (fixed-route tablet, GCRPC Fixed Route); a change to both gets both. A tablet release (ops/release-rideavl.sh) gets its own `apps: [tablet]` note naming the version.
- Skip notes for invisible work (refactors, specs, ops scripts, performance nobody feels).
- Show Philz the note text when asking to commit, so the wording is reviewed.
- If the change affects how to do something, also update the guide in `docs/help/*.md`.

## Deploying a change on the live server (.16)
- Code reloading is OFF (config/environments/development.rb, 2026-09-29): editing a file changes nothing until `docker restart ridepilot_app_1` (about 12 s of downtime). Restart when staff aren't mid-task, and say so.
- Reason: with reloading on, an edit during an Ask RidePilot streaming answer deadlocked the whole app for 6 minutes.

## Design
- Anything staff, drivers or a manager will look at follows `docs/design-language.md` (GCRPC navy/gold, Open Sans, a golden-ratio type ladder, one row per thing, plain words). Read it before building or restyling a screen, printout or board.

