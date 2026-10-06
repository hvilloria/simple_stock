# frozen_string_literal: true

module Cash
  # Everything the day screen reads.
  class DayQuery
    PESO_SALE_GROUPS = %w[efectivo mercado_pago banco].freeze

    # One row of the day's list: a single movement, or a transfer's two legs
    # with the outflow leg first.
    Entry = Struct.new(:kind, :movements, :counts_in_drawer, keyword_init: true) do
      def movement = movements.first
      def from = movements.first.account
      def to = movements.last.account
      def amount = movements.first.amount.abs
    end

    # A saved movement or transfer is rendered as one row of the list without
    # re-reading the whole day.
    def self.entry_for(movements)
      movements = movements.sort_by { |movement| movement.outflow? ? 0 : 1 }

      Entry.new(kind: kind_of(movements.first), movements: movements,
                counts_in_drawer: movements.any?(&:drawer_account?))
    end

    def self.kind_of(movement)
      return :move if movement.transfer?

      movement.inflow? ? :in : :out
    end
    private_class_method :kind_of

    def initialize(business_date)
      @business_date = business_date
    end

    # The whole day in load order. The kind is read off the stored sign; the
    # server already decided it.
    def entries
      CashMovement
        .on(@business_date)
        .includes(:supplier, paid_invoices: :supplier, source_payment: [ :orders, :cash_movements ])
        .order(:created_at, :id)
        .group_by { |movement| movement.transfer_group_id || movement.id }
        .values
        .map { |movements| self.class.entry_for(movements) }
    end

    def sales_by_channel
      @sales_by_channel ||= CashMovement.on(@business_date).sales.group(:channel).sum(:amount)
    end

    # The day's sales folded into the arca group each channel lands in.
    # Compensation reaches no arca, so it is left out.
    def sales_by_group
      @sales_by_group ||= sales_by_channel.each_with_object(Hash.new(0)) do |(channel, amount), sums|
        account = CashMovement.account_for_channel(channel)
        sums[CashMovement.reporting_group_for(account)] += amount if account
      end
    end

    def peso_sales_total
      sales_by_group.values_at(*PESO_SALE_GROUPS).sum
    end

    def peso_sales_share(group)
      return 0 unless peso_sales_total.positive?

      (sales_by_group[group] * 100 / peso_sales_total).clamp(0, 100).to_f.round(1)
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

    def future?
      @business_date > Date.current
    end

    # --- Closing modal ---------------------------------------------------

    def movement_count
      CashMovement.on(@business_date).count
    end

    # The query behind the sidebar badge, scoped to the date.
    def uncollected_notes_count
      Order.immediate.pending.by_sale_date(@business_date).count
    end

    # The date's collections still waiting for an invoice. A reversed one has
    # nothing left to invoice.
    def unbilled_payments
      collected_today = CashMovement.on(@business_date).where("amount > 0").select(:source_payment_id)
      reversed = CashMovement.sales.where("amount < 0").where.not(source_payment_id: nil).select(:source_payment_id)

      Payment.where(invoice_type: nil, id: collected_today)
             .where.not(id: reversed)
             .includes(:orders)
             .order(:id)
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
