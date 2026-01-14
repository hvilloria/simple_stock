# frozen_string_literal: true

module Web
  class PurchasesController < ApplicationController
    before_action :load_suppliers, only: [ :new, :create ]

    def index
      authorize Purchase
      @purchases = Purchase.includes(:supplier, purchase_items: :product)
                          .order(purchase_date: :desc)
                          .limit(50)
    end

    def new
      @purchase = Purchase.new(currency: "USD", purchase_date: Date.today)
      authorize @purchase
    end

    def create
      authorize Purchase, :create?
      result = Purchasing::CreatePurchase.call(
        supplier: find_supplier,
        items: parse_items,
        currency: params[:currency] || "USD",
        exchange_rate: params[:exchange_rate]&.to_f,
        purchase_date: params[:purchase_date] || Date.today,
        notes: params[:notes]
      )

      if result.success?
        redirect_to web_purchases_path, notice: "Compra registrada exitosamente. Stock actualizado."
      else
        flash.now[:alert] = result.errors.join(", ")
        @purchase = Purchase.new
        load_suppliers
        render :new, status: :unprocessable_entity
      end
    end

    private

    def load_suppliers
      @suppliers = Supplier.order(:name)
    end

    def find_supplier
      Supplier.find(params[:supplier_id])
    end

    def parse_items
      return [] unless params[:purchase_items]

      params[:purchase_items].map do |item|
        {
          product_id: item[:product_id].to_i,
          quantity: item[:quantity].to_i,
          unit_cost: item[:unit_cost].to_f
        }
      end.reject { |item| item[:quantity] <= 0 || item[:unit_cost] < 0 }
    end
  end
end
