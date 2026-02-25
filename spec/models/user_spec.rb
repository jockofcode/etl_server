require "rails_helper"

RSpec.describe User, type: :model do
  subject(:user) { build(:user) }

  describe "validations" do
    it "is valid with valid attributes" do
      expect(user).to be_valid
    end

    it "is invalid without an email" do
      user.email = nil
      expect(user).not_to be_valid
    end

    it "is invalid with a duplicate email (case-insensitive)" do
      create(:user, email: "dup@example.com")
      user.email = "DUP@EXAMPLE.COM"
      expect(user).not_to be_valid
    end

    it "is invalid with a malformed email" do
      user.email = "not-an-email"
      expect(user).not_to be_valid
    end

    it "is invalid with a password shorter than 8 characters" do
      user.password = "short"
      user.password_confirmation = "short"
      expect(user).not_to be_valid
    end
  end

  describe "#authenticate" do
    let!(:saved_user) { create(:user, password: "correctpassword", password_confirmation: "correctpassword") }

    it "returns the user when the password is correct" do
      expect(saved_user.authenticate("correctpassword")).to eq(saved_user)
    end

    it "returns false when the password is wrong" do
      expect(saved_user.authenticate("wrongpassword")).to be false
    end
  end

  describe "email normalization" do
    it "downcases the email before saving" do
      user = create(:user, email: "UPPER@EXAMPLE.COM")
      expect(user.reload.email).to eq("upper@example.com")
    end
  end
end
