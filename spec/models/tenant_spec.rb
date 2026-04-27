require "rails_helper"

RSpec.describe Tenant, type: :model do
  describe "validations" do
    subject { build(:tenant) }

    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:subdomain) }
    it { is_expected.to validate_uniqueness_of(:subdomain) }
  end

  describe "associations" do
    it { is_expected.to have_many(:users).dependent(:destroy) }
    it { is_expected.to have_many(:projects).dependent(:destroy) }
    it { is_expected.to have_many(:tasks).dependent(:destroy) }
  end
end
