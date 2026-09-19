# frozen_string_literal: true

module Cash
  # Everything the day screen reads. The two zones of the design are not a
  # column: the drawer zone is every sale plus whatever was paid out of the
  # till, and the arca zone is the rest.
  class DayQuery
    # One row of the day's list: a single movement, or a transfer's two legs
    # with the outflow leg first.
    Entry = Struct.new(:kind, :movements, :counts_in_drawer, keyword_init: true) do
      def movement = movements.first
      def from = movements.first.account
      def to = movements.last.account
      def amount = movements.first.amount.abs
    end

    def initialize(business_date)
      @business_date = business_date
    end

    # The whole day in load order. The kind is read off the stored sign; the
    # server already decided it.
    def entries
      CashMovement
        .on(@business_date)
        .includes(source_payment: :orders)
        .order(:created_at, :id)
        .group_by { |movement| movement.transfer_group_id || movement.id }
        .values
        .map { |movements| build_entry(movements) }
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

    private

    def build_entry(movements)
      movements = movements.sort_by { |movement| movement.outflow? ? 0 : 1 }

      Entry.new(kind: kind_of(movements.first), movements: movements,
                counts_in_drawer: movements.any?(&:drawer_account?))
    end

    def kind_of(movement)
      return :move if movement.transfer?

      movement.inflow? ? :in : :out
    end
  end
end
