# frozen_string_literal: true

module Web
  class PurchasesController < ApplicationController
    def index
      # TODO: Implementar listado de compras
      @purchases = Purchase.all.order(purchase_date: :desc)
    end
  end
end

