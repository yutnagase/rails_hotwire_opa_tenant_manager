class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: [ :auth0 ]

  acts_as_tenant :tenant

  has_many :tasks, dependent: :nullify

  ROLES = %w[admin member guest].freeze

  validates :auth0_uid, presence: true, uniqueness: true
  validates :name, presence: true
  validates :email, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  # Auth0コールバックから呼ばれる。テナント内でユーザーを検索し、なければ作成する。
  def self.from_omniauth(auth, tenant)
    where(auth0_uid: auth.uid, tenant: tenant).first_or_create! do |user|
      user.email = auth.info.email
      user.name  = auth.info.name || auth.info.email
      user.role  = "member"
    end
  end
end
