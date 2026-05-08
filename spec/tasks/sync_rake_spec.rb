# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'sync rake tasks', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/isilon_import'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task['sync:assets'].reenable if Rake::Task.task_defined?('sync:assets')
    Rake::Task['sync:contentdm_filenames'].reenable if Rake::Task.task_defined?('sync:contentdm_filenames')
    Rake::Task['sync:scrc_manuscripts'].reenable if Rake::Task.task_defined?('sync:scrc_manuscripts')
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

  describe 'sync:contentdm_filenames' do
    it 'calls SyncService::ContentdmFilenameSync with the configured csv paths' do
      result = SyncService::ContentdmFilenameSync::SyncResult.new(
        updated_count: 7,
        rows_touched: 10,
        rows_matched: 6,
        rows_unmatched: 3,
        rows_discarded: 1
      )
      expect(SyncService::ContentdmFilenameSync).to receive(:call).with(csv_folder: 'csv').and_return(result)

      Rake::Task['sync:contentdm_filenames'].invoke('csv')
    end
  end

  describe 'sync:scrc_manuscripts' do
    it 'calls SyncService::ContentdmNonUniqueFilenameSync with the configured csv path' do
      result = SyncService::ContentdmNonUniqueFilenameSync::SyncResult.new(
        updated_count: 2,
        rows_touched: 3,
        rows_matched: 1,
        rows_unmatched: 2,
        rows_discarded: 0
      )
      expect(SyncService::ContentdmNonUniqueFilenameSync).to receive(:call).with(
        file_path: 'csv/scrc_manuscripts_non-unique_filenames.csv'
      ).and_return(result)

      Rake::Task['sync:scrc_manuscripts'].invoke('csv/scrc_manuscripts_non-unique_filenames.csv')
    end
  end
end
