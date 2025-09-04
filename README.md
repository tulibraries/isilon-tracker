

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

* Ingest sample sample data from the repo, if needed (file included in the repo). In some zsh shells with nomatch turned on, escaping the brackets in this command may be necessary. Alternatively, quote the entire task portion of the command, or add "setopt +o nomatch" to your ~/.zshrc profile to prevent zsh from requiring bracket escaping in Rails commands.

```bash
rails sync:assets[\"scan_output.applications-backup.csv\"]
or
rails "sync:assets[scan_output.applications-backup.csv]"
```

* Install node packages and JS dependencies

```bash
bundle exec yarn install
```

### Start the Application for Development

* Start the development server. This command has built-in watching and auto-recompiling of css/js changes.

```bash
bin/dev
```

* Javascript Filetree explorer view available at /volumes, administrate backend at /admin. Omniauth logins required for both.
  Initial seed creates user templelibraries@gmail.com. Pass in 1Password, if needed.

## Running the Tests

* Run `bundle exec rspec` to run the test suite.

* Run `bundle exec rubocop` to run the linter. Add the -A flag to autocorrect: `bundle exec rubocop -A` 
