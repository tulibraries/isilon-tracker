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
end
