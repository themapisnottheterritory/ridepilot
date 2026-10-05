Ridepilot Verson 3
================

The purpose of this project is to implement a Computer Aided Scheduling and Dispatch (CASD) software system to meet the needs of small scale human service transportation agencies. 

Status
-------------
This is **GCRPC's fork** (`themapisnottheterritory/ridepilot`, branch `master`), in production
for Victoria Transit, Goliad County Rural Transit and Lavaca County Transit. It started from
CamSys RidePilot 2.1.12 (2019) and has been developed in-house since; the footer shows the
running build as commit date and hash (see `config/initializers/version.rb`). The CamSys links
below are the original upstream, no longer tracked.

- development: check [develop](https://github.com/camsys/ridepilot/tree/develop)

- latest stable: check [master](https://github.com/camsys/ridepilot/tree/master)

- RidePilot CAD/AVL engine: check [CAD/AVL](https://github.com/camsys/ridepilot_cad_avl)

- RideAVL driver mobile app: check [RideAVL](https://github.com/camsys/rideavl)

Dependencies
-------------

This application requires (versions as run in production, October 2026):

- Ruby 3.2.9
- Rails 7.1.6
- PostgreSQL 9.4 (production runs 9.4.21)
- PostGIS 2.5
- ImageMagick 6
- Redis 7

Set up development environment (native, see below for docker setup)
-------------

1. Install the required versions of Postgresql, PostGIS, and any other system packages required for your setup

2. Application setup
    - `bundle install`
    - Copy `config/application.example.yml` to `config/application.yml` and update the values.

3. Database setup
    - Copy `config/database.yml.example.pg` to `config/database.yml` and update the values for specific environment (at least __development__ and __test__).

    - `rails db:setup`
    - 'rails sql:create_gps_locations_partition'

4. Testing
    - set up test database if not yet
      - make sure `config/database.yml` has the configurations for __test__ environment
    - update schema and locales
      - `rails db:test:prepare`
    - `rspec`

5. Start application
    - `rails s`

Set up docker-based development environment
-------------

1. Install [docker and docker-compose](https://www.docker.com/products/docker-desktop)

2. Configuration
    - Copy `config/database.yml.docker` to `config/database.yml`
    - Copy `config/application.example.yml` to `config/application.yml` and update the values.

3. Build
    - Under RidePilot root directory, run `docker-compose build` to build images
    - Setup local database: `docker-compose run app rails db:setup`
    - Might need to run `docker-compose run app rails ridepilot:load_locales` to add translations

4. Start and stop app
    - `docker-compose up` to start
    - open `localhost` 
    - `CTRL + C` to stop


License
-------
  The RidePilot platform source code is released as open-source software under the GNU Affero General Public License v3 (http://www.gnu.org/licenses/agpl-3.0.en.html) license.