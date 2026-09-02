# frozen_string_literal: true

class CashMovement < ApplicationRecord
  class SealedMovementError < StandardError; end

  ACCOUNT_LABELS = {
    "drawer"       => "Caja del día",
    "main_cash"    => "Caja grande",
    "change_fund"  => "Remanente",
    "bank"         => "Banco",
    "mercado_pago" => "Mercado Pago",
    "usd"          => "USD"
  }.freeze

  CATEGORY_LABELS = {
    "sale"              => "Venta",
    "suppliers"         => "Proveedores",
    "fixed_expense"     => "Gastos fijos",
    "internal_transfer" => "Movimiento entre arcas",
    "partner"           => "Socio",
    "cash_discrepancy"  => "Diferencia de arqueo",
    "opening_balance"   => "Saldo inicial"
  }.freeze

  SUBCATEGORY_LABELS = {
    "rent"           => "Alquiler",
    "salaries"       => "Salarios",
    "social_charges" => "Cargas sociales",
    "taxes"          => "Impuestos",
    "utilities"      => "Servicios",
    "store_expenses" => "Gastos de local"
  }.freeze

  # partner is the one category that goes both ways, so its direction is picked
  # by name instead of typed as a minus. It is not stored: the sign is.
  PARTNER_DIRECTION_LABELS = {
    "withdrawal"   => "Retiro",
    "contribution" => "Aporte"
  }.freeze

  CHANNEL_LABELS = {
    "cash"         => "Efectivo",
    "card"         => "Tarjeta",
    "qr"           => "QR",
    "transfer"     => "Transferencia",
    "mercado_pago" => "Mercado Pago",
    "usd"          => "USD",
    "compensation" => "Compensación"
  }.freeze

  # A sale's channel determines the arca it lands in. Compensation is the one
  # channel that reaches no arca: it bills, but no money moves.
  CHANNEL_ACCOUNTS = {
    "cash"         => "drawer",
    "card"         => "bank",
    "qr"           => "bank",
    "transfer"     => "bank",
    "mercado_pago" => "mercado_pago",
    "usd"          => "usd",
    "compensation" => nil
  }.freeze

  # A payment's method and a cash channel are different vocabularies; this is
  # the one place that translates between them.
  PAYMENT_METHOD_CHANNELS = {
    "cash"          => "cash",
    "bank_qr"       => "qr",
    "bank_card"     => "card",
    "bank_transfer" => "transfer",
    "mercado_pago"  => "mercado_pago"
  }.freeze

  # The coarser grain the balance report reads at, matching the existing
  # Caja Grande sheet. USD stands alone: there is no grand total mixing
  # currencies, on purpose.
  REPORTING_GROUPS = {
    "efectivo"     => %w[drawer main_cash change_fund],
    "banco"        => %w[bank],
    "mercado_pago" => %w[mercado_pago],
    "usd"          => %w[usd]
  }.freeze

  REPORTING_GROUP_LABELS = {
    "efectivo"     => "Efectivo",
    "banco"        => "Banco",
    "mercado_pago" => "Mercado Pago",
    "usd"          => "USD"
  }.freeze

  ACCOUNT_REPORTING_GROUPS = REPORTING_GROUPS.each_with_object({}) do |(group, accounts), lookup|
    accounts.each { |account| lookup[account] = group }
  end.freeze

  belongs_to :daily_closing, optional: true
  belongs_to :source_payment, class_name: "Payment", optional: true
  belongs_to :user

  before_update :prevent_sealed_change
  before_destroy :prevent_sealed_change

  # Suffixed because `mercado_pago` and `usd` are both an account and a
  # channel; without the suffix the predicates would collide.
  enum :account, ACCOUNT_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :category, CATEGORY_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :subcategory, SUBCATEGORY_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true
  enum :channel, CHANNEL_LABELS.keys.to_h { |k| [ k.to_sym, k ] }, suffix: true

  validates :business_date, presence: true
  validates :category, presence: true
  validates :amount, presence: true, numericality: { other_than: 0 }
  validate :account_required_unless_compensation
  validate :channel_only_on_sales
  validate :subcategory_only_on_fixed_expenses

  scope :for_account, ->(account) { where(account: account) }
  scope :on, ->(date) { where(business_date: date) }
  scope :between, ->(from, to) { where(business_date: from..to) }
  scope :sales, -> { where(category: "sale") }

  def self.balance_for(account)
    for_account(account).sum(:amount)
  end

  def self.drawer_balance_on(date)
    for_account("drawer").on(date).sum(:amount)
  end

  def self.account_for_channel(channel)
    CHANNEL_ACCOUNTS.fetch(channel.to_s)
  end

  def self.channel_for_payment_method(method)
    PAYMENT_METHOD_CHANNELS.fetch(method.to_s)
  end

  def self.reporting_group_for(account)
    ACCOUNT_REPORTING_GROUPS.fetch(account.to_s)
  end

  def self.account_label(key) = ACCOUNT_LABELS.fetch(key.to_s, key.to_s)
  def self.category_label(key) = CATEGORY_LABELS.fetch(key.to_s, key.to_s)
  def self.channel_label(key) = CHANNEL_LABELS.fetch(key.to_s, key.to_s)
  def self.subcategory_label(key) = SUBCATEGORY_LABELS.fetch(key.to_s, key.to_s)

  def inflow? = amount.positive?
  def outflow? = amount.negative?
  def partner_direction = outflow? ? "withdrawal" : "contribution"
  def sealed? = daily_closing_id.present?

  # Which zone of the day screen this row belongs to. Same split as
  # Cash::DayQuery: every sale plus whatever moved through the till.
  def drawer_zone? = sale_category? || drawer_account?

  # Born from a collection, not typed into the drawer zone.
  def automatic? = source_payment_id.present?

  # Written as one half of a Cash::RecordTransfer pair; its twin carries the
  # same transfer_group_id.
  def transfer? = transfer_group_id.present?

  # The notes the source payment settled. Plural: one collection on a credit
  # account can settle several. Empty on a typed row.
  def paper_numbers
    return [] if source_payment.nil?

    source_payment.orders.map(&:paper_number).sort
  end

  private

  # Guards on the persisted value, not the assigned one, so Cash::CloseDay can
  # stamp daily_closing_id on a row that has none yet.
  def prevent_sealed_change
    return if daily_closing_id_was.blank?

    raise SealedMovementError,
          "cash movement #{id} is sealed by closing #{daily_closing_id_was}"
  end

  def account_required_unless_compensation
    if compensation_channel?
      if account.present?
        errors.add(:base, "Una venta por compensación no lleva arca: no entra dinero a ninguna caja.")
      end
    elsif account.blank?
      errors.add(:base, "Falta el arca: indicá a qué caja entra o de cuál sale el dinero.")
    end
  end

  def channel_only_on_sales
    if sale_category?
      if channel.blank?
        errors.add(:base, "Falta el canal: indicá cómo entró el dinero de la venta.")
      end
    elsif channel.present?
      errors.add(:base, "El canal solo corresponde a una venta.")
    end
  end

  def subcategory_only_on_fixed_expenses
    if fixed_expense_category?
      if subcategory.blank?
        errors.add(:base, "Falta la subcategoría: indicá de qué tipo de gasto fijo se trata.")
      end
    elsif subcategory.present?
      errors.add(:base, "La subcategoría solo corresponde a un gasto fijo.")
    end
  end
end
