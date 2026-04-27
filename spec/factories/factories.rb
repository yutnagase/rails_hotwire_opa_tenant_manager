FactoryBot.define do
  factory :tenant do
    sequence(:name) { |n| "Company #{n}" }
    sequence(:subdomain) { |n| "company-#{n}" }
  end

  factory :user do
    tenant
    sequence(:auth0_uid) { |n| "auth0|#{n}" }
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    role { "member" }
  end

  factory :project do
    tenant
    sequence(:name) { |n| "Project #{n}" }
  end

  factory :task do
    tenant
    project
    sequence(:name) { |n| "Task #{n}" }
    status { "todo" }
    user { nil }
  end
end
