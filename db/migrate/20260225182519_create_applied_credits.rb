class CreateAppliedCredits < ActiveRecord::Migration[7.2]
  def change
    create_table :applied_credits do |t|
      t.references :credit_note, null: false, foreign_key: true
      t.references :invoice,     null: false, foreign_key: true
      t.decimal    :amount,      precision: 10, scale: 2, null: false
      t.date       :applied_at,  null: false

      t.timestamps
    end
  end
end
