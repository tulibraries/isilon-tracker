# frozen_string_literal: true

require 'rails_helper'
require 'rake'

RSpec.describe 'sync rake tasks', type: :task do
  before(:all) do
    Rake.application.rake_require 'tasks/isilon_import'
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    Rake::Task['sync:tiffs'].reenable if Rake::Task.task_defined?('sync:tiffs')
    Rake::Task['sync:assets'].reenable if Rake::Task.task_defined?('sync:assets')
  end

  describe 'sync:tiffs' do
    let!(:deposit_volume) { create(:volume, name: 'deposit') }
    let!(:media_volume) { create(:volume, name: 'media-repository') }

    context 'with valid volume argument' do
      it 'calls SyncService::Tiffs with the correct volume_name' do
        expect(SyncService::Tiffs).to receive(:call).with(volume_name: 'deposit')

        Rake::Task['sync:tiffs'].invoke('deposit')
      end

      it 'works with media-repository volume' do
        expect(SyncService::Tiffs).to receive(:call).with(volume_name: 'media-repository')

        Rake::Task['sync:tiffs'].invoke('media-repository')
      end
    end

    context 'with missing volume argument' do
      it 'exits with error message' do
        expect { Rake::Task['sync:tiffs'].invoke }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'with invalid volume argument' do
      it 'exits with error for unknown volume name' do
        expect { Rake::Task['sync:tiffs'].invoke('invalid-volume') }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'with volume not in database' do
      it 'exits with error when volume does not exist in database' do
        expect { Rake::Task['sync:tiffs'].invoke('nonexistent') }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
    end

    context 'when service raises an exception' do
      it 'exits with error and shows backtrace' do
        allow(SyncService::Tiffs).to receive(:call).and_raise(StandardError.new('Service failed'))

        expect { Rake::Task['sync:tiffs'].invoke('deposit') }.to raise_error(SystemExit) do |error|
          expect(error.status).to eq(1)
        end
      end
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
end
