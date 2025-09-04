
namespace :users do
  desc "Create or update initial user accounts from environment variables"
  task sync_initial: :environment do
    puts "Syncing initial users from environment variables..."

    created_count = 0
    updated_count = 0
    skipped_count = 0

    initial_users.each do |config|
      email = config[:email]
      user = User.find_by(email: email)
      if user
        if user.status == "active"
          skipped_count += 1
        else
          user.update(status: "active")
          updated_count += 1
        end
      else
        # User doesn't exist - create new account
        user = User.new(
          email: email,
          password: SecureRandom.hex(16),
          status: "active"
        )

        if user.save
          puts "Created user: #{email}"
          created_count += 1
        else
          puts "Failed to create #{email}: #{user.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "\nSummary: Created #{created_count}, Updated #{updated_count}, Skipped #{skipped_count}"
  end

  private

  def initial_users
    emails = []
    # Parse environment variables into user configs
    parse_env_emails("INITIAL_ADMIN_EMAILS").each { |email| emails << { email: email, status: "active" } }
    emails
  end

  def parse_env_emails(env_var)
    ENV.fetch(env_var, "")
        .split(",")
        .map(&:strip)
        .reject(&:blank?)
  end
end
