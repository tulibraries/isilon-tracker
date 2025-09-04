# frozen_string_literal: true

namespace :users do
  desc "Generate random passwords for all existing users"
  task generate_passwords: :environment do
    puts "Generating random passwords for all existing users..."

    updated_count = 0
    error_count = 0

    User.find_each do |user|
      new_password = SecureRandom.hex(16)

      if user.update(password: new_password)
        puts "Updated password for user: #{user.email}"
        updated_count += 1
      else
        puts "Failed to update password for #{user.email}: #{user.errors.full_messages.join(', ')}"
        error_count += 1
      end
    end

    puts "\nSummary: Updated #{updated_count} users, #{error_count} errors"
  end
end
