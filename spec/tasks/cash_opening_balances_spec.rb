# frozen_string_literal: true

require "rails_helper"
require "rake"

RSpec.describe "cash:opening_balances", type: :task do
  let(:task_name) { "cash:opening_balances" }
  let!(:admin) { create(:user, :admin) }

  before(:all) do
    Rails.application.load_tasks unless Rake::Task.task_defined?("cash:opening_balances")
  end

  before do
    ENV["ON"] = "2026-08-31"
    ENV["MAIN_CASH"] = "12497899.30"
    ENV["BANK"] = "2522996.25"
    ENV["MERCADO_PAGO"] = "4285964.02"
    ENV["CHANGE_FUND"] = "101800"
    ENV["USD"] = "500"
  end

  after do
    %w[ON MAIN_CASH BANK MERCADO_PAGO CHANGE_FUND USD DRAWER].each { |k| ENV.delete(k) }
  end

  # Invokes the task while capturing its output, which the task uses to report.
  def run_task
    original = $stdout
    $stdout = StringIO.new
    Rake::Task[task_name].reenable
    Rake::Task[task_name].invoke
    $stdout.string
  ensure
    $stdout = original
  end

  it "creates one opening_balance movement per arca given a value" do
    run_task

    expect(CashMovement.where(category: "opening_balance").count).to eq(5)
    expect(CashMovement.balance_for("main_cash")).to eq(BigDecimal("12497899.30"))
    expect(CashMovement.balance_for("bank")).to eq(BigDecimal("2522996.25"))
    expect(CashMovement.balance_for("usd")).to eq(500)
  end

  it "dates every movement on the given day" do
    run_task

    dates = CashMovement.pluck(:business_date).uniq
    expect(dates).to eq([ Date.new(2026, 8, 31) ])
  end

  it "skips an arca with no value given" do
    run_task

    expect(CashMovement.balance_for("drawer")).to eq(0)
  end

  it "refuses to run twice" do
    run_task

    expect { run_task }.to raise_error(SystemExit)
    expect(CashMovement.where(category: "opening_balance").count).to eq(5)
  end

  describe "a malformed amount" do
    before { ENV["BANK"] = "2.522.996,25" }

    it "persists nothing and leaves the task runnable" do
      expect { run_task }.to raise_error(SystemExit)
      expect(CashMovement.count).to eq(0)

      ENV["BANK"] = "2522996.25"
      run_task
      expect(CashMovement.where(category: "opening_balance").count).to eq(5)
    end
  end

  describe "a missing or malformed date" do
    it "aborts when ON is absent" do
      ENV.delete("ON")

      expect { run_task }.to raise_error(SystemExit)
      expect(CashMovement.count).to eq(0)
    end

    it "aborts when ON is not an ISO date" do
      ENV["ON"] = "08/31/2026"

      expect { run_task }.to raise_error(SystemExit)
      expect(CashMovement.count).to eq(0)
    end
  end

  describe "a negative amount" do
    before { ENV["MAIN_CASH"] = "-500000" }

    it "loads it but warns, naming the arca and the amount" do
      output = run_task

      expect(CashMovement.balance_for("main_cash")).to eq(-500_000)
      expect(output).to match(/Atención.*Caja grande.*-500000/)
    end
  end
end
