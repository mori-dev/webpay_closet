class SalesController < ApplicationController
  before_filter :authenticate_customer!

  # GET /items
  def index
    @sales = Sale.where(customer: current_customer).includes(:item).all
  end
end
