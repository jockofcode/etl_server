FactoryBot.define do
  factory :nas_account do
    association :user
    sequence(:username) { |n| "nas-account-#{n}" }

    transient do
      plain_password { "secret123" }
    end

    after(:build) do |nas_account, evaluator|
      nas_account.password = evaluator.plain_password
    end
  end
end