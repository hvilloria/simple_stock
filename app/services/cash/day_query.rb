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

    def arca_movements
      CashMovement
        .on(@business_date)
        # COALESCE, not a bare comparison: account is nullable, and in SQL
        # NOT (false OR NULL) is NULL, which would drop such a row from BOTH
        # zones and make it vanish from the screen with nothing failing.
        .where.not("category = :sale OR COALESCE(account, '') = :drawer", sale: "sale", drawer: "drawer")
        .includes(source_payment: :orders)
        .order(:created_at, :id)
    end

    def sales_by_channel
      @sales_by_channel ||= CashMovement.on(@business_date).sales.group(:channel).sum(:amount)
    end

    def amount_to_wrap
      CashMovement.drawer_balance_on(@business_date)
    end

    # What the drawer should hold before anyone counts it. Same figure as the
    # amount to wrap: they only diverge once a count is entered.
    def expected_cash
      amount_to_wrap
    end

    def closed?
      DailyClosing.exists?(business_date: @business_date)
    end

    # --- Closing modal ---------------------------------------------------

    def movement_count
      CashMovement.on(@business_date).count
    end

    # The query behind the sidebar badge, scoped to the date.
    def uncollected_notes_count
      Order.immediate.pending.by_sale_date(@business_date).count
    end

    def sales_without_invoice_type_count
      Order.active.by_sale_date(@business_date).where(invoice_type: nil).count
    end

    # The Payway terminal only settles card sales; QR and transfers share the
    # bank arca but are not part of its batch, so the channel is the match.
    def payway_recorded_total
      sales_by_channel["card"] || 0
    end

    def mercado_pago_recorded_total
      sales_by_channel["mercado_pago"] || 0
    end
  end
end
