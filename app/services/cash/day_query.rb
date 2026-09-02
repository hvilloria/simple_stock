# frozen_string_literal: true

module Cash
  # Everything the day screen reads. The two zones of the design are not a
  # column: the drawer zone is every sale plus whatever was paid out of the
  # till, and the arca zone is the rest.
  class DayQuery
    def initialize(business_date)
      @business_date = business_date
    end

    def drawer_movements
      CashMovement
        .on(@business_date)
        .where("category = :sale OR account = :drawer", sale: "sale", drawer: "drawer")
        .includes(source_payment: :orders)
        .order(:created_at, :id)
    end

    def sales_by_channel
      CashMovement.on(@business_date).sales.group(:channel).sum(:amount)
    end

    def amount_to_wrap
      CashMovement.drawer_balance_on(@business_date)
    end

    def closed?
      DailyClosing.exists?(business_date: @business_date)
    end
  end
end
