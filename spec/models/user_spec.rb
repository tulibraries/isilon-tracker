# frozen_string_literal: true

require "rails_helper"

RSpec.describe User, type: :model do
  describe "#display_name" do
    context "when user has a name" do
      let(:user) { FactoryBot.create(:user, name: "John Doe", email: "john@example.com") }

      it "returns the name" do
        expect(user.display_name).to eq("John Doe")
      end
    end

    context "when user has no name" do
      let(:user) { FactoryBot.create(:user, name: nil, email: "john@example.com") }

      it "returns the email as fallback" do
        expect(user.display_name).to eq("john@example.com")
      end
    end

    context "when user has an empty name" do
      let(:user) { FactoryBot.create(:user, name: "", email: "john@example.com") }

      it "returns the email as fallback" do
        expect(user.display_name).to eq("john@example.com")
      end
    end

    context "when user has whitespace-only name" do
      let(:user) { FactoryBot.create(:user, name: "   ", email: "john@example.com") }

      it "returns the email as fallback" do
        expect(user.display_name).to eq("john@example.com")
      end
    end
  end

  # Additional tests for batch actions context
  describe "in batch actions context" do
    let!(:user_with_name) { FactoryBot.create(:user, name: "Jane Smith", email: "jane@temple.edu") }
    let!(:user_without_name) { FactoryBot.create(:user, name: nil, email: "john@temple.edu") }

    it "provides consistent display format for dropdowns" do
      # This test verifies that our display_name method works consistently
      # for the user dropdown in batch actions
      expect(user_with_name.display_name).to eq("Jane Smith")
      expect(user_without_name.display_name).to eq("john@temple.edu")
    end
  end
end
