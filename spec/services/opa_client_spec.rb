require "rails_helper"

RSpec.describe OpaClient, type: :service do
  let(:user) { build(:user, role: "admin") }

  describe ".allowed?" do
    context "when OPA returns true" do
      before { stub_opa_allow }

      it "returns true" do
        expect(OpaClient.allowed?(user: user, action: "read", resource: "project")).to be true
      end
    end

    context "when OPA returns false" do
      before { stub_opa_deny }

      it "returns false" do
        expect(OpaClient.allowed?(user: user, action: "delete", resource: "project")).to be false
      end
    end

    context "when OPA is unreachable" do
      before do
        stub_request(:post, OpaClient::OPA_URL).to_raise(Errno::ECONNREFUSED)
      end

      it "returns false (fail-closed)" do
        expect(OpaClient.allowed?(user: user, action: "read", resource: "project")).to be false
      end
    end
  end
end
