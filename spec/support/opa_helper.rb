module OpaHelper
  def stub_opa_allow
    stub_request(:post, OpaClient::OPA_URL)
      .to_return(status: 200, body: { result: true }.to_json, headers: { "Content-Type" => "application/json" })
  end

  def stub_opa_deny
    stub_request(:post, OpaClient::OPA_URL)
      .to_return(status: 200, body: { result: false }.to_json, headers: { "Content-Type" => "application/json" })
  end
end

RSpec.configure do |config|
  config.include OpaHelper
end
