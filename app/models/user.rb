class User < ApplicationRecord
  has_secure_password
  has_many :api_tokens, dependent: :destroy

  USERNAME_FORMAT = /\A[a-z0-9]([a-z0-9\-]*[a-z0-9])?\z/

  validates :email, presence: true, uniqueness: { case_sensitive: false },
                    format: { with: URI::MailTo::EMAIL_REGEXP }
  validates :password, length: { minimum: 8 }, allow_nil: true
  validates :username,
            format: { with: USERNAME_FORMAT,
                      message: "must contain only lowercase letters, digits, and hyphens, and must not start or end with a hyphen" },
            uniqueness: { case_sensitive: false },
            allow_nil: true

  before_save { self.email = email.downcase }

  # ── SMB credentials (stored encrypted) ────────────────────────────────────

  attr_writer :smb_password

  def smb_password
    return @smb_password if @smb_password
    return nil if smb_password_ciphertext.blank?
    smb_encryptor.decrypt_and_verify(smb_password_ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def smb_connected?
    smb_username.present? && smb_password_ciphertext.present?
  end

  before_save :encrypt_smb_password

  private

  def encrypt_smb_password
    return unless @smb_password
    self.smb_password_ciphertext = @smb_password.present? ? smb_encryptor.encrypt_and_sign(@smb_password) : nil
  end

  def smb_encryptor
    key = ActiveSupport::KeyGenerator.new(
      Rails.application.secret_key_base, iterations: 1000
    ).generate_key("etl_smb_credentials", 32)
    ActiveSupport::MessageEncryptor.new(key)
  end
end
