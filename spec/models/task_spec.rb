require "rails_helper"

RSpec.describe Task, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:status) }
    it { is_expected.to validate_inclusion_of(:status).in_array(Task::STATUSES) }
  end

  describe "associations" do
    it { is_expected.to belong_to(:project) }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:tenant) }
  end
end
