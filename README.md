

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

* There are some environment variables that need to be set in order for login to work locally. You can find these in the 
* 1Password app, in the "dev team" vault. Search for the "Google OAuth Isilon Tracker Dev" note and execute the
  export commands.

```bash
export GOOGLE_OAUTH_CLIENT_ID=XXXXXXXXXX.apps.googleusercontent.com
export GOOGLE_OAUTH_SECRET=XXXXXXXXXX
```

* Authentication is required. Click on the "Sign in with GoogleOauth2" button and
  connect to your Google account. If you encounter the Google Account Profile Page, return to Isilon tracker
  application and reauthenticate. You should be take to the desired page. NOTE: This is a known issue which
  we will address in a future release.

* To seed initial users from the command line, use the pattern in the following block. Note, the password is
  required, but not used, since this application only uses oauth2 for authentication.

```bash
bundle exec rails runner "pwd = SecureRandom.alphanumeric(16); u = User.create!(name: 'User Name', email: '<TUACCESS_ID>@temple.edu', password: pwd, status: 'active')"

```

* Ingest sample sample data from the repo, if needed (file included in the repo). 

`bundle exec rails sync:assets[scan_output.applications-backup.csv]`

In some zsh shells with nomatch turned on, escaping the brackets in this command may be necessary. Alternatively, quote the entire task portion of the command, or add "setopt +o nomatch" to your ~/.zshrc profile to prevent zsh from requiring bracket escaping in Rails commands.

```bash
bundle exec rails sync:assets[\"scan_output.applications-backup.csv\"]
or
bundle exec rails "sync:assets[scan_output.applications-backup.csv]"
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
