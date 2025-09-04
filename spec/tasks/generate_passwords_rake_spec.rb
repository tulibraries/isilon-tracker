# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'users:generate_passwords rake task', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/generate_passwords'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task['users:generate_passwords'].reenable
  end

  after(:each) do
    User.delete_all
  end

  describe 'with existing users' do
    let!(:user1) { User.create!(email: 'user1@test.com', password: 'original_password', status: 'active') }
    let!(:user2) { User.create!(email: 'user2@test.com', password: 'another_original', status: 'inactive') }
    let!(:user3) { User.create!(email: 'user3@test.com', password: 'third_password', status: 'active') }

    it 'updates passwords for all users' do
      original_passwords = [ user1, user2, user3 ].map(&:encrypted_password)

      Rake::Task['users:generate_passwords'].invoke

      [ user1, user2, user3 ].each(&:reload)
      new_passwords = [ user1, user2, user3 ].map(&:encrypted_password)

      # All passwords should be different from originals
      original_passwords.each_with_index do |original, index|
        expect(new_passwords[index]).not_to eq(original)
      end
    end
  end
end
