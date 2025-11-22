# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[7.2].define(version: 2025_11_21_180246) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

  create_table "customers", force: :cascade do |t|
    t.string "name", null: false
    t.string "document"
    t.string "phone"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "has_credit_account", default: false, null: false
    t.string "customer_type", default: "retail", null: false
    t.index ["document"], name: "index_customers_on_document"
  end

  create_table "order_items", force: :cascade do |t|
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.decimal "unit_price", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_id"], name: "index_order_items_on_order_id"
    t.index ["product_id"], name: "index_order_items_on_product_id"
  end

  create_table "orders", force: :cascade do |t|
    t.string "status", default: "confirmed", null: false
    t.decimal "total_amount", precision: 10, scale: 2, default: "0.0", null: false
    t.bigint "customer_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "order_type", default: "cash", null: false
    t.string "channel"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["order_type"], name: "index_orders_on_order_type"
    t.index ["status"], name: "index_orders_on_status"
  end

  create_table "payments", force: :cascade do |t|
    t.bigint "customer_id", null: false
    t.decimal "amount", precision: 10, scale: 2, null: false
    t.string "payment_method", null: false
    t.date "payment_date", default: -> { "CURRENT_DATE" }, null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_payments_on_customer_id"
    t.index ["payment_date"], name: "index_payments_on_payment_date"
  end

  create_table "products", force: :cascade do |t|
    t.string "name", null: false
    t.string "sku", null: false
    t.string "category"
    t.decimal "cost_unit", precision: 10, scale: 2
    t.decimal "price_unit", precision: 10, scale: 2
    t.integer "current_stock", default: 0, null: false
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "cost_currency", default: "ARS", null: false
    t.string "origin"
    t.string "product_type"
    t.string "brand"
    t.index ["sku"], name: "index_products_on_sku", unique: true
  end

  create_table "purchase_items", force: :cascade do |t|
    t.bigint "purchase_id", null: false
    t.bigint "product_id", null: false
    t.integer "quantity", null: false
    t.decimal "unit_cost", precision: 10, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_purchase_items_on_product_id"
    t.index ["purchase_id"], name: "index_purchase_items_on_purchase_id"
  end

  create_table "purchases", force: :cascade do |t|
    t.bigint "supplier_id", null: false
    t.string "currency", default: "USD", null: false
    t.decimal "exchange_rate", precision: 10, scale: 4
    t.date "purchase_date", null: false
    t.string "status", default: "confirmed", null: false
    t.decimal "total_cost", precision: 10, scale: 2
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purchase_date"], name: "index_purchases_on_purchase_date"
    t.index ["supplier_id"], name: "index_purchases_on_supplier_id"
  end

  create_table "stock_locations", force: :cascade do |t|
    t.string "name", null: false
    t.string "code"
    t.string "address"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "stock_movements", force: :cascade do |t|
    t.bigint "product_id", null: false
    t.bigint "stock_location_id", null: false
    t.integer "quantity", null: false
    t.string "movement_type", null: false
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "reference_type"
    t.bigint "reference_id"
    t.index ["movement_type"], name: "index_stock_movements_on_movement_type"
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
    t.index ["reference_type", "reference_id"], name: "index_stock_movements_on_reference_type_and_reference_id"
    t.index ["stock_location_id"], name: "index_stock_movements_on_stock_location_id"
  end

  create_table "suppliers", force: :cascade do |t|
    t.string "name"
    t.string "contact_name"
    t.string "phone"
    t.string "email"
    t.text "address"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "order_items", "orders"
  add_foreign_key "order_items", "products"
  add_foreign_key "orders", "customers"
  add_foreign_key "payments", "customers"
  add_foreign_key "purchase_items", "products"
  add_foreign_key "purchase_items", "purchases"
  add_foreign_key "purchases", "suppliers"
  add_foreign_key "stock_movements", "products"
  add_foreign_key "stock_movements", "stock_locations"
end
