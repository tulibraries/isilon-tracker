

# Isilon Tracker

This application creates a filetree view of assets stored in the Isilon file storage system. It allows for updating of 
metadata for each object ingested from CSV files exported from the Isilon server. Metadata is meant to facilitate the 
transfer of all data from the Isilon to a new storage system, giving users the ability to track migration status, assign 
users to assets, and assign assets to digital collections for organization and tracking.

## Getting Started

### Install the application

```bash
git clone git@github.com:tulibraries/isilon-tracker
cd isilon-tracker
bundle install
```

* Initialize the db and populate wtih seeds from config

```bash
bundle exec rails db:setup
```

* Ingest sample sample data from the repo, if needed (file included in the repo)

```bash
rails sync:assets["scan_output.applications-backup.csv"]
```

(note: in zsh shells, it may be necesary to escape the brackets in the above command. You can avoid this by setting 'setopt nonomatch' in your .zshrc file)

* Install node packages and JS dependencies

```bash
bundle exec yarn install
```

### Start the Application for Development

* Start the development server. This command has built-in watching and auto-recompiling of css/js changes.

```bash
bin/dev
```

* Javascript Filetree explorer view available at root path, administrate backend at /admin. Omniauth logins required for both.
  Initial seed creates user templelibraries@gmail.com. Pass in 1pass, if needed.

## Running the Tests

* Run `bundle exec rspec` to run the test suite.

* Run `bundle exec rubocop` to run the linter. Add the -A flag to autocorrect: `bundle exec rubocop -A` 
