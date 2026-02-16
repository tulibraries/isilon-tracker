# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'sync rake tasks', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/isilon_import'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    if Rake::Task.task_defined?('sync:assets')
      Rake::Task['sync:assets'].reenable
    end

    if Rake::Task.task_defined?('sync:refresh_folder_descendant_assets')
      Rake::Task['sync:refresh_folder_descendant_assets'].reenable
    end
  end

  describe 'sync:assets' do
    context 'with csv_path argument' do
      it 'calls SyncService::Assets with the correct csv_path' do
        expect(SyncService::Assets).to receive(:call).with(csv_path: '/path/to/file.csv')

        Rake::Task['sync:assets'].invoke('/path/to/file.csv')
      end
    end

    context 'without csv_path argument' do
      it 'calls SyncService::Assets with nil csv_path' do
        expect(SyncService::Assets).to receive(:call).with(csv_path: nil)

        Rake::Task['sync:assets'].invoke
      end
    end
  end

  describe 'sync:refresh_folder_descendant_assets' do
    it 'marks ancestors of assets and clears empty folders' do
      volume = create(:volume, name: 'Test Volume')
      root_folder = create(:isilon_folder,
        volume: volume,
        parent_folder: nil,
        full_path: '/Root',
        has_descendant_assets: true)
      child_folder = create(:isilon_folder,
        volume: volume,
        parent_folder: root_folder,
        full_path: '/Root/Child',
        has_descendant_assets: false)
      empty_folder = create(:isilon_folder,
        volume: volume,
        parent_folder: nil,
        full_path: '/Empty',
        has_descendant_assets: true)

      create(:isilon_asset, parent_folder: child_folder, volume: volume)

      Rake::Task['sync:refresh_folder_descendant_assets'].invoke

      expect(root_folder.reload.has_descendant_assets).to be(true)
      expect(child_folder.reload.has_descendant_assets).to be(true)
      expect(empty_folder.reload.has_descendant_assets).to be(false)
    end
  end
end
