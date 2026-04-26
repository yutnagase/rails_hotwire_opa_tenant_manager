class Project < ApplicationRecord
  acts_as_tenant :tenant

  has_many :tasks, dependent: :destroy

  validates :name, presence: true
end
