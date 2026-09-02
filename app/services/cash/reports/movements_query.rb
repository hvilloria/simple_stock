# frozen_string_literal: true

module Cash
  module Reports
    # The drill-down of the balance report: the rows behind a figure.
    #
    # The arca filter takes a reporting GROUP and matches every fine arca in
    # it, while the screen shows the fine arca. Filtering at the grain the
    # report reads at is what keeps a filtered history adding up to the report
    # it explains.
    class MovementsQuery
      def self.call(from:, to:, group: nil, category: nil, search: nil)
        new(from: from, to: to, group: group, category: category, search: search).call
      end

      def initialize(from:, to:, group: nil, category: nil, search: nil)
        @from = from
        @to = to
        @group = group.to_s
        @category = category.to_s
        @search = search.to_s.strip
      end

      def call = relation

      # A relation and not an array: the controller paginates it, so the page
      # is cut in SQL rather than in Ruby.
      def relation
        scoped = CashMovement.between(@from, @to)
                             .includes(source_payment: :orders)
                             .order(business_date: :desc, created_at: :desc, id: :desc)
        scoped = scoped.where(account: accounts) if accounts
        scoped = scoped.where(category: @category) if category?
        scoped = scoped.where("description ILIKE ?", "%#{escaped_search}%") if @search.present?
        scoped
      end

      private

      # An unknown group narrows nothing rather than returning an empty screen:
      # a typed URL is not a reason to hide the history.
      def accounts = CashMovement::REPORTING_GROUPS[@group]

      def category? = CashMovement::CATEGORY_LABELS.key?(@category)

      def escaped_search = CashMovement.sanitize_sql_like(@search)
    end
  end
end
