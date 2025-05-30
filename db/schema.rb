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

ActiveRecord::Schema[7.2].define(version: 2025_05_30_130711) do
  create_table "isilon_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_size"
    t.string "file_type"
    t.string "isilon_path", null: false
    t.string "isilon_name", null: false
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
    t.integer "isilon_folders_id"
    t.index ["isilon_folders_id"], name: "index_isilon_assets_on_isilon_folders_id"
    t.index ["isilon_path"], name: "index_isilon_assets_on_isilon_path", unique: true
  end

  create_table "isilon_folders", force: :cascade do |t|
    t.string "full_path", null: false
    t.integer "volume_id"
    t.integer "parent_folder_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["full_path"], name: "index_isilon_folders_on_full_path", unique: true
    t.index ["parent_folder_id"], name: "index_isilon_folders_on_parent_folder_id"
    t.index ["volume_id"], name: "index_isilon_folders_on_volume_id"
  end

  create_table "volumes", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "isilon_assets", "isilon_folders", column: "isilon_folders_id"
  add_foreign_key "isilon_folders", "isilon_folders", column: "parent_folder_id"
  add_foreign_key "isilon_folders", "volumes"
end
