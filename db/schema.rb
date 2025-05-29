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

ActiveRecord::Schema[7.2].define(version: 2025_05_29_205111) do
  create_table "isilon_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_size"
    t.string "file_type"
    t.string "isilon_path"
    t.string "isilon_name"
    t.string "last_modified_in_isilon"
    t.string "date_created_in_isilon"
    t.string "migration_status", default: "pending"
    t.string "contentdm_collection"
    t.string "aspace_collection"
    t.string "preservica_reference_id"
    t.string "aspace_linking_status"
    t.text "notes"
    t.string "assigned_to", default: "unassigned"
    t.string "last_updated_by"
    t.string "file_checksum"
    t.index ["isilon_path"], name: "index_isilon_assets_on_isilon_path", unique: true
  end

  create_table "isilon_folders", force: :cascade do |t|
    t.string "full_path"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
