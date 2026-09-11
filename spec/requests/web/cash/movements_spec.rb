# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::Cash::Movements", type: :request do
  let(:cashier) { create(:user, role: "caja") }
  let(:date)    { "2026-08-03" }

  before { sign_in cashier }

  def post_movement(params)
    post "/web/cash/movements",
         params: { business_date: date }.merge(params),
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end

  describe "POST /web/cash/movements" do
    it "records a cash sale against the drawer" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "324.700,00")

      movement = CashMovement.last
      expect(movement.category).to eq("sale")
      expect(movement.account).to eq("drawer")
      expect(movement.amount).to eq(324_700)
      expect(movement.business_date).to eq(Date.new(2026, 8, 3))
    end

    it "routes a card sale to the bank without asking" do
      post_movement(category: "sale", channel: "card", description: "Venta tarjeta", amount: "54.700,00")

      expect(CashMovement.last.account).to eq("bank")
    end

    it "records an expense as an outflow from the drawer" do
      post_movement(category: "fixed_expense", subcategory: "store_expenses", description: "Bolsas", amount: "13.000,00")

      movement = CashMovement.last
      expect(movement.amount).to eq(-13_000)
      expect(movement.account).to eq("drawer")
    end

    it "answers with a turbo stream that appends the row" do
      post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "1.000,00")

      expect(response.media_type).to eq("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="append"', 'target="drawer-rows"')
      expect(response.body).to include('target="drawer-live-row"')
    end

    it "refuses an amount that is not a number and writes nothing" do
      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "abc")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a sale with no channel" do
      expect {
        post_movement(category: "sale", channel: "", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a category the drawer zone does not offer" do
      expect {
        post_movement(category: "internal_transfer", description: "Traspaso", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a zero amount and writes nothing" do
      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "0,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("El monto no puede ser cero.")
    end

    it "refuses to write into a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      expect {
        post_movement(category: "sale", channel: "cash", description: "Tarde", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "turns a seller away" do
      sign_in create(:user, role: "vendedor")

      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end
  end

  describe "every category the drawer zone offers" do
    it "loads each one end to end" do
      post_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      post_movement(category: "suppliers", description: "Cromosol", amount: "2.000,00")
      post_movement(category: "fixed_expense", subcategory: "store_expenses", description: "Bolsas", amount: "3.000,00")

      expect(CashMovement.pluck(:category)).to contain_exactly("sale", "suppliers", "fixed_expense")
    end

    it "refuses a fixed expense with no subcategory, which is why the row offers one" do
      expect {
        post_movement(category: "fixed_expense", description: "Bolsas", amount: "3.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses a subcategory on a category that is not a fixed expense" do
      expect {
        post_movement(category: "suppliers", subcategory: "store_expenses", description: "Cromosol", amount: "2.000,00")
      }.not_to change(CashMovement, :count)
    end
  end

  describe "the arca zone" do
    def post_arca_movement(params)
      post_movement({ account: "bank" }.merge(params))
    end

    it "records a supplier payment against the arca the cashier declared" do
      post_arca_movement(category: "suppliers", description: "Cromosol", amount: "153.951,00")

      movement = CashMovement.last
      expect(movement.category).to eq("suppliers")
      expect(movement.account).to eq("bank")
      expect(movement.amount).to eq(-153_951)
    end

    it "records a fixed expense against a bundle" do
      post_arca_movement(account: "main_cash", category: "fixed_expense", subcategory: "salaries",
                         description: "Sueldos", amount: "400.000,00")

      movement = CashMovement.last
      expect(movement.account).to eq("main_cash")
      expect(movement.subcategory).to eq("salaries")
      expect(movement.amount).to eq(-400_000)
    end

    it "answers with a stream that appends to the arca zone and refreshes its live row" do
      post_arca_movement(category: "suppliers", description: "Cromosol", amount: "153.951,00")

      expect(response.body).to include('action="append"', 'target="arca-rows"')
      expect(response.body).to include('target="arca-live-row"')
      expect(response.body).not_to include('target="drawer-live-row"')
    end

    it "leaves the amount to wrap untouched when the arca is not the drawer" do
      expect {
        post_arca_movement(category: "suppliers", description: "Cromosol", amount: "153.951,00")
      }.not_to change { ::Cash::DayQuery.new(Date.new(2026, 8, 3)).amount_to_wrap }
    end

    it "puts the same expense in the drawer zone when it came out of the till" do
      post_arca_movement(account: "drawer", category: "suppliers", description: "Cromosol", amount: "153.951,00")

      movement = CashMovement.last
      expect(movement.account).to eq("drawer")
      expect(movement).to be_drawer_zone
      expect(response.body).to include('action="append"', 'target="drawer-rows"')
      expect(response.body).to include('target="arca-live-row"')
    end

    it "moves the amount to wrap when the arca is the drawer" do
      expect {
        post_arca_movement(account: "drawer", category: "suppliers", description: "Cromosol", amount: "153.951,00")
      }.to change { ::Cash::DayQuery.new(Date.new(2026, 8, 3)).amount_to_wrap }.by(-153_951)
    end

    it "refuses a sale, which belongs to the drawer zone" do
      expect {
        post_arca_movement(category: "sale", channel: "cash", description: "Venta", amount: "1.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses a category the arca zone does not offer" do
      expect {
        post_arca_movement(category: "internal_transfer", description: "Traspaso", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "refuses an arca that does not exist" do
      expect {
        post_arca_movement(account: "colchon", category: "suppliers", description: "Cromosol", amount: "1.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses to write into a closed day" do
      create(:daily_closing, business_date: Date.new(2026, 8, 3))

      expect {
        post_arca_movement(category: "suppliers", description: "Cromosol", amount: "1.000,00")
      }.not_to change(CashMovement, :count)
    end

    it "keeps the error on the arca live row" do
      post_arca_movement(category: "suppliers", description: "Cromosol", amount: "0,00")

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include('target="arca-live-row"')
      expect(response.body).to include("El monto no puede ser cero.")
    end

    describe "correcting an arca row" do
      let(:movement) do
        create(:cash_movement, :supplier_payment, business_date: Date.new(2026, 8, 3), user: cashier)
      end

      it "opens a form row that offers the arca" do
        get "/web/cash/movements/#{movement.id}/edit",
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.body).to include('name="account"')
        expect(response.body).to include("Banco")
      end

      it "corrects the arca in place" do
        patch "/web/cash/movements/#{movement.id}",
              params: { account: "main_cash", category: "suppliers",
                        description: "Cromosol", amount: "153.951,00" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(movement.reload.account).to eq("main_cash")
        expect(movement.amount).to eq(-153_951)
      end

      it "offers no correction on a closed day" do
        movement
        create(:daily_closing, business_date: Date.new(2026, 8, 3))

        get "/web/cash/days/2026-08-03"

        expect(response.body).to include("Cromosol")
        expect(response.body).not_to include("Editar")
      end

      it "offers no correction on a transfer leg" do
        create(:cash_movement, :transfer_leg, business_date: Date.new(2026, 8, 3),
               account: "main_cash", amount: -1_000, description: "Traspaso")

        get "/web/cash/days/2026-08-03"

        expect(response.body).to include("Traspaso")
        expect(response.body).not_to include("Editar")
      end
    end
  end

  describe "correcting a row" do
    let(:business_date) { Date.new(2026, 8, 3) }
    let(:movement) do
      create(:cash_movement, business_date: business_date, user: cashier,
             description: "Venta mostrador", amount: 324_700)
    end

    def patch_movement(record, params)
      patch "/web/cash/movements/#{record.id}",
            params: params,
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    def delete_movement(record)
      delete "/web/cash/movements/#{record.id}",
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end

    describe "GET /web/cash/movements/:id/edit" do
      it "swaps the row for a form row" do
        get "/web/cash/movements/#{movement.id}/edit",
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include('action="replace"', %(target="cash_movement_#{movement.id}"))
        expect(response.body).to include("Venta mostrador")
      end

      it "refuses to open a form on a closed day" do
        create(:daily_closing, business_date: business_date)

        get "/web/cash/movements/#{movement.id}/edit",
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end

      it "turns a seller away" do
        movement
        sign_in create(:user, role: "vendedor")

        get "/web/cash/movements/#{movement.id}/edit"

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end
    end

    describe "PATCH /web/cash/movements/:id" do
      it "corrects the amount in place" do
        patch_movement(movement, category: "sale", channel: "cash",
                                 description: "Venta mostrador", amount: "300.000,00")

        expect(movement.reload.amount).to eq(300_000)
      end

      it "re-routes the arca when the channel changes" do
        patch_movement(movement, category: "sale", channel: "card",
                                 description: "Venta mostrador", amount: "324.700,00")

        expect(movement.reload.account).to eq("bank")
      end

      it "drops the channel and flips the sign when the category stops being a sale" do
        patch_movement(movement, category: "suppliers", description: "Cromosol", amount: "324.700,00")

        movement.reload
        expect(movement.channel).to be_nil
        expect(movement.account).to eq("drawer")
        expect(movement.amount).to eq(-324_700)
      end

      it "answers with a stream that puts the saved row back" do
        patch_movement(movement, category: "sale", channel: "cash",
                                 description: "Venta corregida", amount: "1.000,00")

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include('action="replace"', %(target="cash_movement_#{movement.id}"))
        expect(response.body).to include("Venta corregida")
      end

      it "refuses an amount that is not a number and leaves the row untouched" do
        expect {
          patch_movement(movement, category: "sale", channel: "cash",
                                   description: "Venta mostrador", amount: "abc")
        }.not_to change { movement.reload.amount }

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "refuses a category the drawer zone does not offer" do
        expect {
          patch_movement(movement, category: "partner", description: "Retiro", amount: "1.000,00")
        }.not_to change { movement.reload.category }
      end

      it "refuses a zero amount and leaves the row untouched" do
        expect {
          patch_movement(movement, category: "sale", channel: "cash",
                                   description: "Venta mostrador", amount: "0,00")
        }.not_to change { movement.reload.amount }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.body).to include("El monto no puede ser cero.")
      end

      it "refuses a day that was closed in another tab" do
        movement
        create(:daily_closing, business_date: business_date)

        expect {
          patch_movement(movement, category: "sale", channel: "cash",
                                   description: "Tarde", amount: "1.000,00")
        }.not_to change { movement.reload.description }

        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end

      it "refuses a sealed movement with a redirect and a flash, not a 500" do
        sealed = create(:cash_movement, :sealed, business_date: business_date, user: cashier)

        expect {
          patch_movement(sealed, category: "sale", channel: "cash",
                                 description: "Corrección tardía", amount: "1.000,00")
        }.not_to change { sealed.reload.description }

        expect(response).to have_http_status(:redirect)
        expect(response).not_to have_http_status(:internal_server_error)
        expect(flash[:alert]).to be_present
      end

      it "refuses a movement born from a collection with a redirect and a flash, not a 500" do
        automatic = create(:cash_movement, :from_collection, business_date: business_date, user: cashier,
                           description: "Cobro a cuenta")

        expect {
          patch_movement(automatic, category: "sale", channel: "cash",
                                    description: "Corrección a mano", amount: "1.000,00")
        }.not_to change { automatic.reload.description }

        expect(response).to have_http_status(:redirect)
        expect(response).not_to have_http_status(:internal_server_error)
        expect(flash[:alert]).to be_present
      end

      it "turns a seller away" do
        movement
        sign_in create(:user, role: "vendedor")

        expect {
          patch_movement(movement, category: "sale", channel: "cash",
                                   description: "Venta ajena", amount: "1.000,00")
        }.not_to change { movement.reload.description }
      end
    end

    describe "DELETE /web/cash/movements/:id" do
      it "removes the row" do
        movement

        expect { delete_movement(movement) }.to change(CashMovement, :count).by(-1)
      end

      it "answers with a stream that removes the row" do
        id = movement.id
        delete_movement(movement)

        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(response.body).to include('action="remove"', %(target="cash_movement_#{id}"))
      end

      it "refuses a day that was closed in another tab" do
        movement
        create(:daily_closing, business_date: business_date)

        expect { delete_movement(movement) }.not_to change(CashMovement, :count)
        expect(response).to have_http_status(:redirect)
        expect(flash[:alert]).to be_present
      end

      it "refuses a sealed movement with a redirect and a flash, not a 500" do
        sealed = create(:cash_movement, :sealed, business_date: business_date, user: cashier)

        expect { delete_movement(sealed) }.not_to change(CashMovement, :count)
        expect(response).to have_http_status(:redirect)
        expect(response).not_to have_http_status(:internal_server_error)
        expect(flash[:alert]).to be_present
      end

      it "refuses a movement born from a collection with a redirect and a flash, not a 500" do
        automatic = create(:cash_movement, :from_collection, business_date: business_date, user: cashier)

        expect { delete_movement(automatic) }.not_to change(CashMovement, :count)
        expect(response).to have_http_status(:redirect)
        expect(response).not_to have_http_status(:internal_server_error)
        expect(flash[:alert]).to be_present
      end

      it "turns a seller away" do
        movement
        sign_in create(:user, role: "vendedor")

        expect { delete_movement(movement) }.not_to change(CashMovement, :count)
      end
    end
  end

  describe "partner movements" do
    let(:admin) { create(:user, role: "admin") }

    def post_partner(params)
      post_movement({ account: "main_cash", category: "partner" }.merge(params))
    end

    it "records what the partner took as an outflow from the arca the admin declared" do
      sign_in admin

      post_partner(direction: "withdrawal", description: "Retiro", amount: "500.000,00")

      movement = CashMovement.last
      expect(movement.category).to eq("partner")
      expect(movement.account).to eq("main_cash")
      expect(movement.amount).to eq(-500_000)
      expect(movement).not_to be_drawer_zone
    end

    it "records what he put back as an inflow under the same category" do
      sign_in admin

      post_partner(direction: "contribution", description: "Aporte", amount: "500.000,00")

      movement = CashMovement.last
      expect(movement.category).to eq("partner")
      expect(movement.amount).to eq(500_000)
    end

    it "refuses one with no direction rather than guessing the sign" do
      sign_in admin

      expect {
        post_partner(description: "Retiro", amount: "500.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Indicá si el socio retira o aporta.")
    end

    it "refuses one in the drawer zone, where it never belonged" do
      sign_in admin

      expect {
        post_movement(category: "partner", direction: "withdrawal", description: "Retiro", amount: "500.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "refuses one forged by the cashier with a redirect and a flash, not a 500" do
      expect {
        post_partner(direction: "withdrawal", description: "Retiro", amount: "500.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:redirect)
      expect(response).not_to have_http_status(:internal_server_error)
      expect(flash[:alert]).to be_present
    end

    it "refuses a correction that turns her own row into a partner one" do
      movement = create(:cash_movement, :supplier_payment, business_date: Date.new(2026, 8, 3), user: cashier)

      expect {
        patch "/web/cash/movements/#{movement.id}",
              params: { account: "main_cash", category: "partner", direction: "withdrawal",
                        description: "Retiro", amount: "500.000,00" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.not_to change { movement.reload.category }

      expect(response).to have_http_status(:redirect)
      expect(flash[:alert]).to be_present
    end

    it "offers the category in the admin's arca selector and not in the cashier's" do
      sign_in admin
      get "/web/cash/days/2026-08-03"
      expect(response.body).to include('value="partner"')

      sign_in cashier
      get "/web/cash/days/2026-08-03"
      expect(response.body).not_to include('value="partner"')
    end

    it "offers the direction to the admin alone, alongside the category it belongs to" do
      sign_in admin
      get "/web/cash/days/2026-08-03"
      expect(response.body).to include('value="withdrawal"', 'value="contribution"')

      sign_in cashier
      get "/web/cash/days/2026-08-03"
      expect(response.body).not_to include('value="withdrawal"')
    end
  end

  describe "compensation sales" do
    let!(:supplier) { create(:supplier, name: "Cromosol") }

    it "names the supplier whose debt the sale cancels" do
      post_movement(category: "sale", channel: "compensation", supplier_id: supplier.id,
                    description: "Compensación Cromosol", amount: "661.188,00")

      movement = CashMovement.last
      expect(movement.channel).to eq("compensation")
      expect(movement.supplier).to eq(supplier)
      expect(movement.account).to be_nil
      expect(movement.amount).to eq(661_188)
    end

    it "refuses one with no supplier and writes nothing" do
      expect {
        post_movement(category: "sale", channel: "compensation", supplier_id: "",
                      description: "Compensación", amount: "661.188,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to include("Falta el proveedor")
    end

    it "refuses a supplier on a sale that reached an arca" do
      expect {
        post_movement(category: "sale", channel: "cash", supplier_id: supplier.id,
                      description: "Venta mostrador", amount: "1.000,00")
      }.not_to change(CashMovement, :count)

      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "offers the supplier in the drawer live row, which the cash sale then leaves unsent" do
      get "/web/cash/days/2026-08-03"

      expect(response.body).to include("cash-live-row-target=\"supplier\"", "Cromosol")

      expect {
        post_movement(category: "sale", channel: "cash", description: "Venta mostrador", amount: "1.000,00")
      }.to change(CashMovement, :count).by(1)
      expect(CashMovement.last.supplier).to be_nil
    end

    it "keeps the supplier when the row is corrected" do
      movement = create(:cash_movement, :compensation_sale, business_date: Date.new(2026, 8, 3),
                                                            supplier: supplier, user: cashier)

      patch "/web/cash/movements/#{movement.id}",
            params: { business_date: date, category: "sale", channel: "compensation",
                      supplier_id: supplier.id, description: "Compensación", amount: "700.000,00" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      movement.reload
      expect(movement.amount).to eq(700_000)
      expect(movement.supplier).to eq(supplier)
    end

    it "offers the supplier in the edit row of a compensation sale" do
      movement = create(:cash_movement, :compensation_sale, business_date: Date.new(2026, 8, 3),
                                                            supplier: supplier, user: cashier)

      get "/web/cash/movements/#{movement.id}/edit",
          headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("cash-live-row-target=\"supplier\"")
      expect(response.body).to include(%(selected="selected" value="#{supplier.id}"))
    end
  end
end
