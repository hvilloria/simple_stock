class ConvertStockMovementReferenceToPolymorphic < ActiveRecord::Migration[7.2]
  def up
    # Add new polymorphic columns
    add_column :stock_movements, :reference_type, :string
    add_column :stock_movements, :reference_id, :bigint

    # Migrate existing data
    migrated_count = 0
    null_count = 0
    moved_to_notes_count = 0

    StockMovement.where.not(reference: nil).find_each do |movement|
      # Try to extract Order ID from reference like "ORDER-123"
      if movement.reference =~ /ORDER-(\d+)/i
        order_id = $1.to_i
        
        if Order.exists?(order_id)
          movement.update_columns(
            reference_type: "Order",
            reference_id: order_id
          )
          migrated_count += 1
        else
          # Order doesn't exist, move to notes
          existing_note = movement.note.present? ? "#{movement.note}\n" : ""
          movement.update_columns(
            note: "#{existing_note}[Migrated reference: #{movement.reference}]"
          )
          moved_to_notes_count += 1
        end
      else
        # Reference doesn't match pattern, move to notes
        existing_note = movement.note.present? ? "#{movement.note}\n" : ""
        movement.update_columns(
          note: "#{existing_note}[Migrated reference: #{movement.reference}]"
        )
        moved_to_notes_count += 1
      end
    end

    # Log migration results
    puts "=== Stock Movement Reference Migration ==="
    puts "Successfully migrated to Order references: #{migrated_count}"
    puts "Moved to notes (pattern not matched or Order not found): #{moved_to_notes_count}"
    puts "Already null: #{StockMovement.where(reference: nil).count}"
    puts "==========================================="

    # Remove old column
    remove_column :stock_movements, :reference

    # Add index for polymorphic association
    add_index :stock_movements, [:reference_type, :reference_id]
  end

  def down
    # Add back the string reference column
    add_column :stock_movements, :reference, :string

    # Remove index
    remove_index :stock_movements, [:reference_type, :reference_id]

    # Migrate data back (best effort)
    StockMovement.where.not(reference_type: nil, reference_id: nil).find_each do |movement|
      if movement.reference_type == "Order"
        movement.update_column(:reference, "ORDER-#{movement.reference_id}")
      elsif movement.reference_type == "Purchase"
        movement.update_column(:reference, "PURCHASE-#{movement.reference_id}")
      end
    end

    # Remove polymorphic columns
    remove_column :stock_movements, :reference_type
    remove_column :stock_movements, :reference_id
  end
end
