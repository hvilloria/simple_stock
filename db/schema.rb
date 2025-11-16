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

ActiveRecord::Schema[7.2].define(version: 2025_11_15_194356) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "plpgsql"

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
    t.index ["sku"], name: "index_products_on_sku", unique: true
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
    t.string "reference"
    t.text "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["movement_type"], name: "index_stock_movements_on_movement_type"
    t.index ["product_id"], name: "index_stock_movements_on_product_id"
    t.index ["stock_location_id"], name: "index_stock_movements_on_stock_location_id"
  end

  add_foreign_key "stock_movements", "products"
  add_foreign_key "stock_movements", "stock_locations"
end
