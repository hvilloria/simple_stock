class AddLocationCodeToProducts < ActiveRecord::Migration[7.2]
  def change
    # Agregar columna para código de ubicación física en el depósito
    # Formato: [pasillo][lado][posición][nivel] - Ejemplo: "2D31"
    add_column :products, :location_code, :string

    # Índice para búsquedas por ubicación (no único, varios productos pueden estar en la misma ubicación)
    add_index :products, :location_code
  end
end
