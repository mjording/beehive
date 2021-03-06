#!/bin/sh -e

mkdir -p .beehive_gem_home
export GEM_HOME=.beehive_gem_home
export GEM_PATH=.beehive_gem_home

echo "$FIXTURE_DIR/gems/rack-1.2.1.gem" > /tmp/rack.env

echo "Checking for a config.ru"
if [ ! -f "config.ru" ]; then
  echo "Invalid rack app"
  exit 127
fi

# If there is an isolate file, run Isolate.now!
if [ -f "Isolate" ]; then
  ruby -rubygems -e "require 'isolate'; Isolate.now!"
fi

# If bundler is used
if [ -f "Gemfile" ]; then
  bundle install
fi

# If .gems file exists
if [ -f ".gems" ]; then
  while read line; do
    if [ ! -z "$line" ]; then
      eval "gem install --no-rdoc --no-ri $line"
    fi
  done < ".gems"
fi

echo "Built rack app"