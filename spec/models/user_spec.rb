require "rails_helper"

RSpec.describe User, type: :model do
  let(:tenant) { create(:tenant) }

  describe "validations", tenant: -> { Tenant.last } do
    subject { build(:user, tenant: tenant) }

    before { tenant } # ensure tenant exists before subject

    it { is_expected.to validate_presence_of(:auth0_uid) }
    it { is_expected.to validate_uniqueness_of(:auth0_uid) }
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:email) }
    it { is_expected.to validate_presence_of(:role) }
    it { is_expected.to validate_inclusion_of(:role).in_array(User::ROLES) }
  end

  describe "associations" do
    it { is_expected.to have_many(:tasks).dependent(:nullify) }
    it { is_expected.to belong_to(:tenant) }
  end

  describe ".from_omniauth" do
    let(:auth) do
      OmniAuth::AuthHash.new(
        uid: "auth0|new-user",
        info: { email: "new@example.com", name: "New User" }
      )
    end

    it "creates a new user for the tenant" do
      ActsAsTenant.with_tenant(tenant) do
        expect { User.from_omniauth(auth, tenant) }.to change(User, :count).by(1)
      end
    end

    it "returns existing user on subsequent calls" do
      ActsAsTenant.with_tenant(tenant) do
        user1 = User.from_omniauth(auth, tenant)
        user2 = User.from_omniauth(auth, tenant)
        expect(user1.id).to eq(user2.id)
      end
    end
  end
end
