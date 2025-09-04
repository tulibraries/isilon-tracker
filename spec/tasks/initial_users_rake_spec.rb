# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'users:sync_initial rake task', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/initial_users'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task['users:sync_initial'].reenable
  end

  after(:each) do
    User.delete_all
  end

  describe 'with valid email addresses' do
    before do
      allow(ENV).to receive(:fetch).with('INITIAL_ADMIN_EMAILS', '').and_return('user1@test.com,user2@test.com,user3@test.com')
    end

    it 'creates new users from environment variable' do
      expect { Rake::Task['users:sync_initial'].invoke }.to change(User, :count).by(3)

      expect(User.find_by(email: 'user1@test.com')).to be_present
      expect(User.find_by(email: 'user2@test.com')).to be_present
      expect(User.find_by(email: 'user3@test.com')).to be_present
    end

    it 'sets all created users to active status' do
      Rake::Task['users:sync_initial'].invoke

      User.all.each do |user|
        expect(user.status).to eq('active')
      end
    end

    it 'assigns random passwords to users' do
      Rake::Task['users:sync_initial'].invoke

      User.all.each do |user|
        expect(user.encrypted_password).to be_present
        expect(user.encrypted_password).not_to be_blank
      end
    end

    it 'outputs summary with correct counts' do
      expect { Rake::Task['users:sync_initial'].invoke }.to output(/Summary: Created 3, Updated 0, Skipped 0/).to_stdout
    end
  end
end
