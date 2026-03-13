class NasAccount < ApplicationRecord
  ENCRYPTION_SALT = "etl_smb_credentials"

  belongs_to :user
  has_many :nas_copy_transfers, dependent: :destroy
  has_many :source_nas_copy_transfers,
           class_name: "NasCopyTransfer",
           foreign_key: :source_nas_account_id,
           dependent: :nullify,
           inverse_of: :source_nas_account

  validates :username,
            presence: true,
            uniqueness: { scope: :user_id, case_sensitive: false }
  validates :password_ciphertext, presence: true
  validate :username_cannot_contain_invalid_path_characters

  before_validation :normalize_username
  before_validation :encrypt_password
  after_save :clear_password_cache

  attr_writer :password

  def password
    return @password if instance_variable_defined?(:@password) && @password.present?
    return nil if password_ciphertext.blank?

    encryptor.decrypt_and_verify(password_ciphertext)
  rescue ActiveSupport::MessageVerifier::InvalidSignature,
         ActiveSupport::MessageEncryptor::InvalidMessage
    nil
  end

  def connected?
    username.present? && password_ciphertext.present?
  end

  private

  def username_cannot_contain_invalid_path_characters
    return if username.blank?
    return unless username.match?(%r{[\\/]}) || username.include?("\x00")

    errors.add(:username, "contains invalid characters")
  end

  def normalize_username
    self.username = username.to_s.strip.downcase.presence
  end

  def encrypt_password
    return unless instance_variable_defined?(:@password)

    self.password_ciphertext = @password.present? ? encryptor.encrypt_and_sign(@password) : nil
  end

  def clear_password_cache
    remove_instance_variable(:@password) if instance_variable_defined?(:@password)
  end

  def encryptor
    key = ActiveSupport::KeyGenerator.new(
      Rails.application.secret_key_base, iterations: 1000
    ).generate_key(ENCRYPTION_SALT, 32)
    ActiveSupport::MessageEncryptor.new(key)
  end
end