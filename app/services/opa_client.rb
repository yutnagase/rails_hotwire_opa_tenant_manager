require "net/http"
require "json"

class OpaClient
  OPA_URL = URI(ENV.fetch("OPA_URL", "http://opa:8181/v1/data/authz/allow"))

  def self.allowed?(user:, action:, resource:)
    payload = {
      input: {
        user: { role: user.role },
        action: action,
        resource: resource
      }
    }

    response = Net::HTTP.post(OPA_URL, payload.to_json, "Content-Type" => "application/json")
    JSON.parse(response.body).dig("result") == true
  rescue StandardError => e
    Rails.logger.error("[OPA] Request failed: #{e.message}")
    false
  end
end
