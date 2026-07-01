class AddLocationCodeToProducts < ActiveRecord::Migration[7.2]
  def change
    # Add a column for the physical location code in the warehouse
    # Format: [aisle][side][position][level] - Example: "2D31"
    add_column :products, :location_code, :string

    # Index for lookups by location (not unique, several products can be in the same location)
    add_index :products, :location_code
  end
end
