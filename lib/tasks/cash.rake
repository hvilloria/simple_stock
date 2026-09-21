# frozen_string_literal: true

namespace :cash do
  desc "Load the one-time opening balance per arca (ON=YYYY-MM-DD MAIN_CASH=... BANK=...)"
  task opening_balances: :environment do
    if CashMovement.where(category: "opening_balance").exists?
      abort "Opening balances were already loaded. They are a one-time operation."
    end

    raw_date = ENV["ON"]
    abort "Pass the date the balances are taken from, e.g. ON=2026-08-31" if raw_date.blank?

    business_date = begin
      Date.parse(raw_date)
    rescue Date::Error
      abort "ON=#{raw_date} is not a valid date. Use ON=YYYY-MM-DD."
    end

    user = User.where(role: "admin").first
    abort "No admin user found to attribute the opening balances to." if user.nil?

    amounts = CashMovement::ACCOUNT_LABELS.keys.filter_map do |account|
      raw = ENV[account.upcase]
      [ account, raw ] if raw.present?
    end

    abort "No amounts given. Pass at least one, e.g. MAIN_CASH=12497899.30" if amounts.empty?

    ActiveRecord::Base.transaction do
      amounts.each do |account, raw|
        result = Cash::RecordMovement.call(
          business_date: business_date,
          account: account,
          amount: raw,
          category: "opening_balance",
          description: "Saldo inicial",
          user: user
        )

        abort "#{account}: #{result.errors.join(', ')}" if result.failure?

        label = CashMovement.account_label(account)
        puts "#{label}: #{result.record.amount}"
        puts "  Atención: #{label} arranca en negativo (#{result.record.amount})." if result.record.amount.negative?
      end
    end

    puts "Loaded #{amounts.size} opening balances on #{business_date}."
  end
end
