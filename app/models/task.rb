class Task < ApplicationRecord
  acts_as_tenant :tenant

  belongs_to :project
  belongs_to :user, optional: true

  STATUSES = %w[todo doing done].freeze

  validates :name, presence: true
  validates :status, presence: true, inclusion: { in: STATUSES }
end
