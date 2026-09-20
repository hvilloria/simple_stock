# frozen_string_literal: true

module Cash
  module Reports
    # The drill-down of the balance report: the rows behind a figure.
    #
    # The arca filter takes a reporting GROUP and matches every fine arca in
    # it, while the screen shows the fine arca. Filtering at the grain the
    # report reads at is what keeps a filtered history adding up to the report
    # it explains.
    #
    # The channel filter is the only one that reaches a compensation: it lands
    # in no arca, and its category is the same "Venta" every sale carries.
    class MovementsQuery
      def self.call(from:, to:, group: nil, channel: nil, category: nil, search: nil)
        new(from: from, to: to, group: group, channel: channel,
            category: category, search: search).call
      end

      def initialize(from:, to:, group: nil, channel: nil, category: nil, search: nil)
        @from = from
        @to = to
        @group = group.to_s
        @channel = channel.to_s
        @category = category.to_s
        @search = search.to_s.strip
      end

      Totals = Struct.new(:inflow, :outflow, :usd_inflow, :usd_outflow, keyword_init: true) do
        def usd? = !usd_inflow.zero? || !usd_outflow.zero?
      end

      def call = relation

      # A relation and not an array: the controller paginates it, so the page
      # is cut in SQL rather than in Ruby.
      def relation
        filtered.includes(:supplier, :transfer_legs, source_payment: :orders)
                .order(business_date: :desc, created_at: :desc, id: :desc)
      end

      # The foot of the screen sums the filter, not the page on screen. Dollars
      # get their own pair of figures: they never enter a peso sum.
      def totals
        inflows  = sums_by_account(0..)
        outflows = sums_by_account(..0)

        Totals.new(inflow: pesos(inflows), outflow: -pesos(outflows),
                   usd_inflow: usd(inflows), usd_outflow: -usd(outflows))
      end

      private

      def filtered
        scoped = CashMovement.between(@from, @to)
        scoped = scoped.where(account: accounts) if accounts
        scoped = scoped.where(channel: @channel) if channel?
        scoped = scoped.where(category: @category) if category?
        scoped = scoped.where("description ILIKE ?", "%#{escaped_search}%") if @search.present?
        scoped
      end

      # An amount is never zero, so a range open at zero is one side of the ledger.
      def sums_by_account(amounts)
        filtered.where(amount: amounts).group(:account).sum(:amount)
      end

      # A compensation lands in no arca, and it is in pesos like any other sale.
      def pesos(sums) = sums.except("usd").values.sum
      def usd(sums) = sums.fetch("usd", 0)

      # An unknown group narrows nothing rather than returning an empty screen:
      # a typed URL is not a reason to hide the history.
      def accounts = CashMovement::REPORTING_GROUPS[@group]

      def channel? = CashMovement::CHANNEL_LABELS.key?(@channel)

      def category? = CashMovement::CATEGORY_LABELS.key?(@category)

      def escaped_search = CashMovement.sanitize_sql_like(@search)
    end
  end
end
