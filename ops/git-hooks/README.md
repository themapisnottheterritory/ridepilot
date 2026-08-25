# Git hooks

Tracked so everyone gets the same ones. Git does not pick them up automatically —
each clone needs this once:

```sh
git config core.hooksPath ops/git-hooks
```

Check it took with `git config --get core.hooksPath`.

## pre-commit

Refuses a commit whose staged `db/schema.rb` **deletes** a table.

`RAILS_ENV=test rails db:migrate` re-dumps `db/schema.rb` from the *test*
database, which is missing tables that exist in production — `fare_cards`,
`fare_card_data`, `lite_customers`, `lite_trips`, `lite_incidental_trips`,
`lite_unique_riders`. The dump silently drops them, and committing that leaves
anyone who later runs `db:schema:load` with a database missing those tables.

It is easy to miss in review: the same diff also contains a plausible-looking
addition for whatever migration you just wrote, so the stat line reads like an
ordinary change. This was caught twice by hand before the hook existed.

When it fires, the fix is almost always to re-dump from development:

```sh
git checkout db/schema.rb
docker exec ridepilot_app_1 sh -c 'cd /var/www/ridepilot && bin/rails db:schema:dump'
git add db/schema.rb
git diff --cached db/schema.rb | grep '^-' | grep -v '^---'   # should print nothing
```

If a migration genuinely drops a table, the hook is wrong for that commit —
say so explicitly with `git commit --no-verify`.
