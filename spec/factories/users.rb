FactoryBot.define do
  factory :user do
    email { "user@exammple.com" }
    password { "password123" }
    name { "Example Name" }
  end
end
