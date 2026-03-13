class NasCopyTransfer < ApplicationRecord
  belongs_to :user
  belongs_to :nas_account, optional: true
  belongs_to :source_nas_account,
             class_name: "NasAccount",
             optional: true,
             inverse_of: :source_nas_copy_transfers

  STATUSES = %w[queued done failed].freeze

  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :active, -> { where(status: "queued") }

  def source_path
    source_nas_path.presence || local_path
  end
end
