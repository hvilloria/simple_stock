# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Closings", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { Date.new(2026, 8, 3) }

  def post_closing(params)
    post "/web/cash/days/#{date}/closing", params: params
  end

  describe "POST /web/cash/days/:day_business_date/closing" do
    before { sign_in cashier }

    it "closes the day and seals its movements" do
      movement = create(:cash_movement, business_date: date, amount: 311_700)

      post_closing(counted_cash: "311.700,00")

      expect(response).to redirect_to(web_cash_day_path(date))
      expect(DailyClosing.exists?(business_date: date)).to be true
      expect(movement.reload.daily_closing_id).to be_present
    end

    it "accepts an amount in Argentine format" do
      create(:cash_movement, business_date: date, amount: 311_700)

      post_closing(counted_cash: "311.700,00")

      expect(DailyClosing.find_by(business_date: date).counted_cash).to eq(311_700)
    end

    it "refuses a non-numeric amount and writes nothing" do
      create(:cash_movement, business_date: date, amount: 311_700)

      expect {
        post_closing(counted_cash: "abc")
      }.not_to change(DailyClosing, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses to close an already-closed day and writes nothing" do
      create(:daily_closing, business_date: date)

      expect {
        post_closing(counted_cash: "0,00")
      }.not_to change(DailyClosing, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "authorization" do
    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      post_closing(counted_cash: "0,00")

      expect(response).to redirect_to(authenticated_root_path)
    end
  end
end
