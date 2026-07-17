require "rails_helper"

RSpec.describe "Inactive user access", type: :request do
  let(:user) do
    create(
      :user,
      status: :active
    )
  end

  it "allows an active user to access the application" do
    sign_in user

    get root_path

    expect(response).to have_http_status(:ok)
  end

  it "signs out a user after their status becomes inactive" do
    sign_in user

    user.inactive_status!

    get root_path

    expect(response).to redirect_to(
      new_user_session_path
    )
  end
end
