# frozen_string_literal: true

module Web
  class CustomersController < ApplicationController
    before_action :set_customer, only: %i[show edit update]

    def index
      authorize Customer
      @customers = Customer.where.not(name: "Cliente Mostrador").order(name: :asc)
    end

    def show
      authorize @customer
      @credit_orders = @customer.orders
                                .where(order_type: "credit")
                                .where.not(status: "cancelled")
                                .order(created_at: :desc)
      @payments = @customer.payments.order(payment_date: :desc)
      @current_balance = @customer.current_balance
    end

    def new
      @customer = Customer.new
      authorize @customer
    end

    def create
      @customer = Customer.new(customer_params)
      authorize @customer

      if @customer.save
        redirect_to web_customer_path(@customer), notice: "Cliente creado exitosamente."
      else
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      authorize @customer
    end

    def update
      authorize @customer

      if @customer.update(customer_params)
        redirect_to web_customer_path(@customer), notice: "Cliente actualizado exitosamente."
      else
        render :edit, status: :unprocessable_entity
      end
    end

    private

    def set_customer
      @customer = Customer.find(params[:id])
    end

    def customer_params
      params.require(:customer).permit(:name, :document, :phone, :customer_type, :has_credit_account)
    end
  end
end
