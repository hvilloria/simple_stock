module Web
  class ProductsController < ApplicationController
    def index
      @products = Product.order(:name)
    end
  end
end
