class User < ApplicationRecord
  devise :omniauthable, omniauth_providers: [ :auth0 ]

  acts_as_tenant :tenant

  has_many :tasks, dependent: :nullify

  ROLES = %w[admin member guest].freeze

  validates :auth0_uid, presence: true, uniqueness: { scope: :tenant_id }
  validates :name, presence: true
  validates :email, presence: true
  validates :role, presence: true, inclusion: { in: ROLES }

  # Auth0コールバックから呼ばれる。
  # 1. auth0_uidで既存ユーザーを検索（ログイン済みユーザー）
  # 2. emailでseedユーザーを検索し、auth0_uidを紐付け（初回ログイン）
  # 3. 見つからなければguestとして新規作成
  def self.from_omniauth(auth, tenant)
    # 既にauth0_uidで紐付け済みのユーザー
    user = find_by(auth0_uid: auth.uid, tenant: tenant)
    return user if user

    # emailでseedユーザーを検索して紐付け
    user = find_by(email: auth.info.email, tenant: tenant)
    if user
      user.update!(auth0_uid: auth.uid, name: auth.info.name || user.name)
      return user
    end

    # 新規ユーザーをguestで作成
    create!(
      tenant: tenant,
      auth0_uid: auth.uid,
      email: auth.info.email,
      name: auth.info.name || auth.info.email,
      role: "guest"
    )
  end
end
