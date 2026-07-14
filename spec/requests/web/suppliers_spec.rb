# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Web::SuppliersController", type: :request do
  include Devise::Test::IntegrationHelpers

  let(:user) { create(:user, role: "admin") }

  before do
    sign_in user
  end

  describe "GET /web/suppliers" do
    it "shows all suppliers" do
      supplier1 = create(:supplier, name: "Proveedor A")
      supplier2 = create(:supplier, name: "Proveedor B")

      get web_suppliers_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Proveedor A")
      expect(response.body).to include("Proveedor B")
    end

    it "orders suppliers alphabetically" do
      create(:supplier, name: "Zebra Parts")
      create(:supplier, name: "Alpha Motors")

      get web_suppliers_path

      expect(response).to have_http_status(:success)
      expect(response.body.index("Alpha Motors")).to be < response.body.index("Zebra Parts")
    end
  end

  describe "GET /web/suppliers/new" do
    it "renders the new supplier form" do
      get new_web_supplier_path

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Nuevo Proveedor")
    end

    it "shows early payment discount fields" do
      get new_web_supplier_path

      expect(response.body).to include("Descuento por Pronto Pago")
      expect(response.body).to include("early_payment_days")
      expect(response.body).to include("early_payment_discount_percentage")
    end
  end

  describe "POST /web/suppliers" do
    context "with valid parameters" do
      it "creates a supplier with basic info" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Nuevo Proveedor",
              email: "contacto@proveedor.com",
              phone: "11-1234-5678"
            }
          }
        }.to change(Supplier, :count).by(1)

        expect(response).to redirect_to(web_suppliers_path)
        follow_redirect!
        expect(response.body).to include("Proveedor creado exitosamente")
      end

      it "creates a supplier with banking info" do
        post web_suppliers_path, params: {
          supplier: {
            name: "Proveedor con Banco",
            bank_alias: "MI.ALIAS.CBU",
            bank_account: "0170000040000012345678"
          }
        }

        supplier = Supplier.last
        expect(supplier.bank_alias).to eq("MI.ALIAS.CBU")
        expect(supplier.bank_account).to eq("0170000040000012345678")
      end

      it "creates a supplier with payment terms" do
        post web_suppliers_path, params: {
          supplier: {
            name: "Proveedor con Plazo",
            payment_term_days: 30
          }
        }

        supplier = Supplier.last
        expect(supplier.payment_term_days).to eq(30)
      end

      it "creates a supplier with early payment discount" do
        post web_suppliers_path, params: {
          supplier: {
            name: "Proveedor con Descuento",
            payment_term_days: 30,
            early_payment_days: 15,
            early_payment_discount_percentage: 5
          }
        }

        supplier = Supplier.last
        expect(supplier.early_payment_days).to eq(15)
        expect(supplier.early_payment_discount_percentage).to eq(5)
        expect(supplier.has_early_payment_discount?).to be true
      end

      it "creates a supplier with all fields" do
        post web_suppliers_path, params: {
          supplier: {
            name: "Proveedor Completo",
            email: "info@completo.com",
            phone: "11-9999-8888",
            cuit: "20-12345678-9",
            bank_alias: "COMPLETO.ALIAS",
            bank_account: "1234567890123456789012",
            payment_term_days: 45,
            early_payment_days: 15,
            early_payment_discount_percentage: 5
          }
        }

        supplier = Supplier.last
        expect(supplier.name).to eq("Proveedor Completo")
        expect(supplier.email).to eq("info@completo.com")
        expect(supplier.phone).to eq("11-9999-8888")
        expect(supplier.cuit).to eq("20-12345678-9")
        expect(supplier.bank_alias).to eq("COMPLETO.ALIAS")
        expect(supplier.bank_account).to eq("1234567890123456789012")
        expect(supplier.payment_term_days).to eq(45)
        expect(supplier.early_payment_days).to eq(15)
        expect(supplier.early_payment_discount_percentage).to eq(5)
      end
    end

    context "with invalid parameters" do
      it "fails without name" do
        expect {
          post web_suppliers_path, params: {
            supplier: { name: "" }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with duplicate name" do
        create(:supplier, name: "Existente")

        expect {
          post web_suppliers_path, params: {
            supplier: { name: "Existente" }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with invalid email format" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Email Malo",
              email: "email-invalido"
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with negative payment_term_days" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Plazo Negativo",
              payment_term_days: -5
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with negative early_payment_days" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Early Negativo",
              early_payment_days: -10
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with early_payment_discount_percentage over 100" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Descuento Alto",
              early_payment_discount_percentage: 150
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "fails with early_payment_discount_percentage of 0" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Descuento Cero",
              early_payment_discount_percentage: 0
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end

    context "early payment validation rules" do
      it "requires both early_payment fields if one is present (days without percentage)" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Solo Dias",
              early_payment_days: 15
              # missing early_payment_discount_percentage
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "requires both early_payment fields if one is present (percentage without days)" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Solo Porcentaje",
              early_payment_discount_percentage: 5
              # missing early_payment_days
            }
          }
        }.not_to change(Supplier, :count)

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it "succeeds when both early_payment fields are nil" do
        expect {
          post web_suppliers_path, params: {
            supplier: {
              name: "Proveedor Sin Descuento"
            }
          }
        }.to change(Supplier, :count).by(1)

        supplier = Supplier.last
        expect(supplier.has_early_payment_discount?).to be false
      end
    end
  end

  describe "GET /web/suppliers/:id" do
    it "shows supplier details" do
      supplier = create(:supplier, :with_early_payment_discount, name: "Goicochea")

      get web_supplier_path(supplier)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Goicochea")
    end

    it "shows supplier with early payment discount configured" do
      supplier = create(:supplier,
                        name: "Con Descuento",
                        early_payment_days: 15,
                        early_payment_discount_percentage: 5)

      get web_supplier_path(supplier)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Con Descuento")
      # Verify supplier has discount configured
      expect(supplier.has_early_payment_discount?).to be true
    end
  end

  describe "GET /web/suppliers/:id/edit" do
    it "renders the edit form" do
      supplier = create(:supplier, name: "Editable")

      get edit_web_supplier_path(supplier)

      expect(response).to have_http_status(:success)
      expect(response.body).to include("Editar")
      expect(response.body).to include("Editable")
    end

    it "shows early payment discount fields" do
      supplier = create(:supplier, :with_early_payment_discount)

      get edit_web_supplier_path(supplier)

      expect(response.body).to include("Descuento por Pronto Pago")
      expect(response.body).to include("early_payment_days")
    end

    it "does not allow editing name" do
      supplier = create(:supplier, name: "No Editable")

      get edit_web_supplier_path(supplier)

      # Name field should be disabled/read-only
      expect(response.body).to include("El nombre no se puede editar")
    end
  end

  describe "PATCH /web/suppliers/:id" do
    let(:supplier) { create(:supplier, name: "Original") }

    context "with valid parameters" do
      it "updates supplier info" do
        patch web_supplier_path(supplier), params: {
          supplier: {
            email: "nuevo@email.com",
            phone: "11-0000-1111"
          }
        }

        expect(response).to redirect_to(web_supplier_path(supplier))
        supplier.reload
        expect(supplier.email).to eq("nuevo@email.com")
        expect(supplier.phone).to eq("11-0000-1111")
      end

      it "updates early payment discount" do
        patch web_supplier_path(supplier), params: {
          supplier: {
            early_payment_days: 10,
            early_payment_discount_percentage: 3
          }
        }

        supplier.reload
        expect(supplier.early_payment_days).to eq(10)
        expect(supplier.early_payment_discount_percentage).to eq(3)
        expect(supplier.has_early_payment_discount?).to be true
      end

      it "removes early payment discount by setting both to nil" do
        supplier_with_discount = create(:supplier, :with_early_payment_discount)

        patch web_supplier_path(supplier_with_discount), params: {
          supplier: {
            early_payment_days: "",
            early_payment_discount_percentage: ""
          }
        }

        supplier_with_discount.reload
        expect(supplier_with_discount.early_payment_days).to be_nil
        expect(supplier_with_discount.early_payment_discount_percentage).to be_nil
        expect(supplier_with_discount.has_early_payment_discount?).to be false
      end

      it "does not change the name even if provided" do
        patch web_supplier_path(supplier), params: {
          supplier: {
            name: "Nombre Nuevo",
            email: "updated@email.com"
          }
        }

        supplier.reload
        expect(supplier.name).to eq("Original") # Name unchanged
        expect(supplier.email).to eq("updated@email.com") # Other fields updated
      end
    end

    context "with invalid parameters" do
      it "fails with invalid email format" do
        patch web_supplier_path(supplier), params: {
          supplier: { email: "invalid-email" }
        }

        expect(response).to have_http_status(:unprocessable_entity)
        supplier.reload
        expect(supplier.email).not_to eq("invalid-email")
      end

      it "fails when setting only early_payment_days without percentage" do
        patch web_supplier_path(supplier), params: {
          supplier: {
            early_payment_days: 15,
            early_payment_discount_percentage: ""
          }
        }

        expect(response).to have_http_status(:unprocessable_entity)
      end
    end
  end

  describe "DELETE /web/suppliers/:id" do
    it "deletes supplier without invoices" do
      supplier = create(:supplier, name: "Para Borrar")

      expect {
        delete web_supplier_path(supplier)
      }.to change(Supplier, :count).by(-1)

      expect(response).to redirect_to(web_suppliers_path)
    end

    it "fails to delete supplier with invoices" do
      supplier = create(:supplier)
      create(:invoice, :simple_mode, supplier: supplier)

      expect {
        delete web_supplier_path(supplier)
      }.not_to change(Supplier, :count)

      # Verify supplier still exists
      expect(Supplier.exists?(supplier.id)).to be true
    end
  end
end
