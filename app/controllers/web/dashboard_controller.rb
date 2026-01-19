module Web
  class DashboardController < ApplicationController
    def index
      authorize :dashboard, :index?
      # Métricas principales
      @sales_today = calculate_sales_today
      @low_stock_count = Product.with_low_stock.count
      @total_receivable = calculate_total_receivable
      @invoices_this_month = calculate_invoices_this_month

      # Datos para secciones secundarias
      @recent_orders = Order.confirmed_status
                            .order(created_at: :desc)
                            .limit(5)
                            .includes(:customer)

      @low_stock_products = Product.with_low_stock
                                   .order(:current_stock)
                                   .limit(10)
    end

    private

    def calculate_sales_today
      Order.confirmed_status
           .where(created_at: Date.today.all_day)
           .sum(:total_amount)
    end

    def calculate_total_receivable
      Customer.with_credit_account.sum(&:current_balance)
    end

    def calculate_invoices_this_month
      return 0 unless defined?(Invoice)

      Invoice.where(status: "confirmed")
              .where(purchase_date: Date.today.beginning_of_month..Date.today.end_of_month)
              .sum(:total_cost)
    end
  end
end
