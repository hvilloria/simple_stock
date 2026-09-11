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

      def call = relation

      # A relation and not an array: the controller paginates it, so the page
      # is cut in SQL rather than in Ruby.
      def relation
        scoped = CashMovement.between(@from, @to)
                             .includes(:supplier, :transfer_legs, source_payment: :orders)
                             .order(business_date: :desc, created_at: :desc, id: :desc)
        scoped = scoped.where(account: accounts) if accounts
        scoped = scoped.where(channel: @channel) if channel?
        scoped = scoped.where(category: @category) if category?
        scoped = scoped.where("description ILIKE ?", "%#{escaped_search}%") if @search.present?
        scoped
      end

      private

      # An unknown group narrows nothing rather than returning an empty screen:
      # a typed URL is not a reason to hide the history.
      def accounts = CashMovement::REPORTING_GROUPS[@group]

      def channel? = CashMovement::CHANNEL_LABELS.key?(@channel)

      def category? = CashMovement::CATEGORY_LABELS.key?(@category)

      def escaped_search = CashMovement.sanitize_sql_like(@search)
    end
  end
end
