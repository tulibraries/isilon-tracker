# README

This README documents steps necessary to get the
application up and running.

* Clone the repo locally

* cd into cloned repo and bundle install, updating ruby if needed

* From the password vault app, in the "dev team" vault, search for the IMT_USER_LIST note and execute the export command

* From the password vault app, in the "dev team" vault, search for the "Google OAuth Isilon Tracker Dev" note and execute the
  export commands

* Run rails db:setup to initialize db and populate wtih seeds from config

* Run rails sync:assets["scan_output.applications-backup.csv"] (included in the repo) for sample data

* Run bin/dev to start the development server and watch for css/js changes

* If authentication is required, you will see the login page. Click on the "Sign in with GoogleOauth2" button and
  connect to your Google account. If you encounter the Google Account Profile Page, return to Isilon tracker
  application and reauthenticate. You should be take to the desired page. NOTE: This is a known issue which
  we will address in a future release.

* Javascript Filetree explorer view available at root path, administrate backend at /admin. Omniauth logins required for both.
  Initial seed creates user templelibraries@gmail.com. Pass in 1pass, if needed.

* Tests run through 'rspec spec'; linting through 'rubocop' add the -A flag to autocorrect

# About this app

This application creates a filetree view of assets stored in the Isilon file storage system. It allows for updating of 
metadata for each object ingested from CSV files exported from the Isilon server. Metadata is meant to facilitate the 
transfer of all data from the Isilon to a new storage system, giving users the ability to track migration status, assign 
users to assets, and assign assets to digital collections for organization and tracking.
