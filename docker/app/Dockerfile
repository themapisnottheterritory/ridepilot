# Base our image on an official, minimal image of our preferred Ruby
FROM ruby:3.2-bullseye

# Install essential Linux packages
RUN apt-get clean && apt-get update -qq && apt-get install -y build-essential libpq-dev nodejs postgresql-client

# Install git
RUN apt-get -y install git

# Install Proj (Required for rgeo-proj4)
RUN apt-get update && apt-get install -y \
    libproj-dev proj-bin

# Imagemagick
RUN apt-get install imagemagick libmagickwand-dev -y

# Define where our application will live inside the image
ENV RAILS_ROOT /var/www/ridepilot

# Create application home. App server will need the pids dir so just create everything in one shot
RUN mkdir -p $RAILS_ROOT/tmp/pids

# Set our working directory inside the image
WORKDIR $RAILS_ROOT

ENV RAILS_ENV='development'
ENV RACK_ENV='development' 

# Copy engines first (needed for Gemfile path dependencies)
COPY engines /var/www/engines

# Use the Gemfiles as Docker cache markers. Always bundle before copying app src.
# (the src likely changed and we don't want to invalidate Docker's cache too early)
# http://ilikestuffblog.com/2014/01/06/how-to-skip-bundle-install-when-deploying-a-rails-app-to-docker/
COPY ridepilot/Gemfile Gemfile
COPY ridepilot/Gemfile.lock Gemfile.lock

# Prevent bundler warnings; ensure that the bundler version executed is >= that which created Gemfile.lock
#RUN bundle update paperclip --full-index
#RUN bundle update marcel --full-index
RUN gem install bundler -v 2.4.22
# Removed bundle update mimemagic - no longer needed with Ruby 3.2

# Upgrade RubyGems before running bundle install
# Upgrade RubyGems to the latest version compatible with Ruby 3.0
RUN gem update --system 3.5.23


# Finish establishing our Ruby enviornment
RUN bundle install

# Copy the Rails application into place
COPY ridepilot .

EXPOSE 3000

CMD ["bundle", "exec", "puma", "-C", "config/puma.rb"]