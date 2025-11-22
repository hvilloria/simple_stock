# frozen_string_literal: true

module Web
  class CustomersController < ApplicationController
    def index
      # TODO: Implementar listado de clientes
      @customers = Customer.all.order(name: :asc)
    end
  end
end

