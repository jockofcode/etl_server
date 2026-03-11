class NasCopyTransfer < ApplicationRecord
  belongs_to :user

  STATUSES = %w[queued done failed].freeze

  scope :recent, -> { order(created_at: :desc).limit(20) }
  scope :active, -> { where(status: "queued") }
end
