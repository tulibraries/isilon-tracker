# frozen_string_literal: true

require "rails_helper"
require "ostruct"

RSpec.describe User, type: :model do
  subject { build(:user) }

  it "is invalid without an email" do
    user = build(:user, email: nil)
    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("can't be blank")
  end

  it "requires a unique email" do
    create(:user, email: "tester@example.com")
    user = build(:user, email: "tester@example.com")
    user.send(:assign_names_from_name_field)

    expect(user).not_to be_valid
    expect(user.errors[:email]).to include("has already been taken")
  end

  it "defines expected statuses" do
    expect(User.statuses.keys).to contain_exactly("inactive", "active")
  end

  it "allows setting and querying status" do
    user = create(:user, status: :active)
    expect(user).to be_active_status
    user.inactive_status!
    expect(user).to be_inactive_status
  end

  describe "#title" do
    it "returns the name if present" do
      user = build(:user, name: "Jennifer", email: "jennifer@example.com")
      expect(user.title).to eq("Jennifer")
    end

    it "falls back to email prefix if name is blank" do
      user = build(:user, name: nil, email: "tester@temple.edu")
      expect(user.title).to eq("Tester")
    end
  end

  describe ".from_omniauth" do
    let(:auth_hash) do
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: "123456",
        info: {
          email: "tester@temple.edu",
          name: "Tester Temple"
        }
      )
    end

    it "creates a new user if none exists" do
      user = User.from_omniauth(auth_hash)
      expect(user.email).to eq("tester@temple.edu")
      expect(user.name).to eq("Tester Temple")
    end

    it "finds existing user by email" do
      existing = create(:user, email: "tester@temple.edu")
      user = User.from_omniauth(auth_hash)
      expect(user.id).to eq(existing.id)
    end

    it "fills in missing name on existing user" do
      existing = create(:user, email: "tester@temple.edu", name: nil)
      user = User.from_omniauth(auth_hash)
      expect(user.name).to eq("Tester Temple")
    end

    it "splits the full name into first and last" do
      access_token = OpenStruct.new(info: { "email" => "jane@example.com", "name" => "Jane Doe" })

      user = User.from_omniauth(access_token)

      expect(user.first_name).to eq("Jane")
      expect(user.last_name).to eq("Doe")
    end

    it "handles a single name gracefully" do
      access_token = OpenStruct.new(info: { "email" => "solo@example.com", "name" => "Prince" })

      user = User.from_omniauth(access_token)

      expect(user.first_name).to eq("Prince")
      expect(user.last_name).to be_nil
    end
  end

  describe "password generation" do
    it "generates a password if one is not provided" do
      user = User.new(email: "test@example.com")

      expect(user.password).to be_nil

      user.valid? # triggers before_validation
      expect(user.password).to be_present
    end

    it "does not overwrite an existing password" do
      user = User.new(email: "test@example.com", password: "custompass")

      user.valid?
      expect(user.password).to eq("custompass")
    end
  end
end
