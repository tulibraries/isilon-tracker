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

ActiveRecord::Schema[7.2].define(version: 2025_09_12_130000) do
  create_table "admins", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_admins_on_email", unique: true
    t.index ["reset_password_token"], name: "index_admins_on_reset_password_token", unique: true
  end

  create_table "aspace_collections", force: :cascade do |t|
    t.string "name"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_aspace_collections_on_name"
  end

  create_table "contentdm_collections", force: :cascade do |t|
    t.string "name"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_contentdm_collections_on_name"
  end

  create_table "isilon_assets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "file_size"
    t.string "file_type"
    t.string "isilon_path", null: false
    t.string "isilon_name", null: false
    t.string "last_modified_in_isilon"
    t.string "date_created_in_isilon"
    t.string "preservica_reference_id"
    t.string "aspace_linking_status"
    t.text "notes"
    t.string "last_updated_by"
    t.string "file_checksum"
    t.integer "parent_folder_id"
    t.integer "migration_status_id"
    t.integer "aspace_collection_id"
    t.integer "contentdm_collection_id"
    t.integer "duplicate_of_id"
    t.integer "assigned_to"
    t.index ["aspace_collection_id"], name: "index_isilon_assets_on_aspace_collection_id"
    t.index ["assigned_to"], name: "index_isilon_assets_on_assigned_to"
    t.index ["contentdm_collection_id"], name: "index_isilon_assets_on_contentdm_collection_id"
    t.index ["duplicate_of_id"], name: "index_isilon_assets_on_duplicate_of_id"
    t.index ["file_checksum"], name: "index_isilon_assets_on_file_checksum"
    t.index ["isilon_path"], name: "index_isilon_assets_on_isilon_path", unique: true
    t.index ["migration_status_id"], name: "index_isilon_assets_on_migration_status_id"
    t.index ["parent_folder_id"], name: "index_isilon_assets_on_parent_folder_id"
  end

  create_table "isilon_folders", force: :cascade do |t|
    t.string "full_path", null: false
    t.integer "volume_id"
    t.integer "parent_folder_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "assigned_to"
    t.text "notes"
    t.index ["assigned_to"], name: "index_isilon_folders_on_assigned_to"
    t.index ["parent_folder_id"], name: "index_isilon_folders_on_parent_folder_id"
    t.index ["volume_id", "full_path"], name: "index_isilon_folders_on_volume_id_and_full_path", unique: true
    t.index ["volume_id"], name: "index_isilon_folders_on_volume_id"
  end

  create_table "migration_statuses", force: :cascade do |t|
    t.string "name"
    t.boolean "default"
    t.boolean "active"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_migration_statuses_on_name"
  end

  create_table "users", force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "provider"
    t.string "uid"
    t.string "name"
    t.string "status", default: "inactive"
    t.string "first_name"
    t.string "last_name"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "volumes", force: :cascade do |t|
    t.string "name", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "isilon_assets", "aspace_collections"
  add_foreign_key "isilon_assets", "contentdm_collections"
  add_foreign_key "isilon_assets", "isilon_assets", column: "duplicate_of_id"
  add_foreign_key "isilon_assets", "isilon_folders", column: "parent_folder_id"
  add_foreign_key "isilon_assets", "migration_statuses"
  add_foreign_key "isilon_assets", "users", column: "assigned_to"
  add_foreign_key "isilon_folders", "isilon_folders", column: "parent_folder_id"
  add_foreign_key "isilon_folders", "users", column: "assigned_to"
  add_foreign_key "isilon_folders", "volumes"
end
