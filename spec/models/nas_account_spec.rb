require "rails_helper"

RSpec.describe NasAccount, type: :model do
  subject(:nas_account) { build(:nas_account, user: user) }

  let(:user) { create(:user) }

  describe "validations" do
    it "is valid with a user, username, and password" do
      expect(nas_account).to be_valid
    end

    it "allows NAS usernames with underscores" do
      nas_account.username = "office_admin"

      expect(nas_account).to be_valid
    end

    it "normalizes the username before validation" do
      nas_account.username = "Mixed-Case-User"

      expect(nas_account).to be_valid
      expect(nas_account.username).to eq("mixed-case-user")
    end

    it "requires usernames to be unique per user" do
      create(:nas_account, user: user, username: "shared-user")
      duplicate = build(:nas_account, user: user, username: "SHARED-USER")

      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:username]).to include("has already been taken")
    end

    it "rejects slashes in usernames" do
      nas_account.username = "bad/name"

      expect(nas_account).not_to be_valid
      expect(nas_account.errors[:username]).to include("contains invalid characters")
    end
  end

  describe "password storage" do
    it "encrypts and decrypts the password" do
      nas_account.username = "alpha-user"
      nas_account.password = "topsecret123"
      nas_account.save!

      expect(nas_account.password_ciphertext).to be_present
      expect(nas_account.password_ciphertext).not_to eq("topsecret123")
      expect(nas_account.reload.password).to eq("topsecret123")
    end
  end
end