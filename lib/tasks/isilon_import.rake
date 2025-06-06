# frozen_string_literal: true

namespace :sync do
  desc "sync isilon assets"
  task :assets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Assets.call(csv_path: args[:path])
  end

  desc "threaded sync of isilon assets"
  task :threadedassets, [ :path ] => :environment do |_t, args|
    args.with_defaults(path: nil)
    SyncService::Threadedassets.call(csv_path: args[:path])
  end
end
