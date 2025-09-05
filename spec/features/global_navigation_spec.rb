require 'rails_helper'

RSpec.describe 'Global Navigation', type: :feature do
  let(:user) { create(:user) }

  describe 'navigation bar' do
    context 'when visiting the main application' do
      before do
        # Create collections so vocabularies dropdown appears
        create(:aspace_collection, name: 'Test Aspace Collection')
        create(:contentdm_collection, name: 'Test ContentDM Collection')

        sign_in user
        visit root_path
      end

      it 'displays the app name in the navbar' do
        expect(page).to have_css('.navbar-brand', text: 'Isilon Tracker')
      end

      it 'has all main navigation items' do
        within('.custom-navbar') do
          expect(page).to have_link('Volumes')
          expect(page).to have_link('Reports')
          expect(page).to have_link('Vocabularies')
          expect(page).to have_link('Users')
        end
      end

      it 'has dropdown menus for volumes and vocabularies' do
        within('.custom-navbar') do
          expect(page).to have_css('.nav-link.dropdown-toggle', text: 'Volumes')
          expect(page).to have_css('.nav-link.dropdown-toggle', text: 'Vocabularies')
        end
      end

      it 'includes Bootstrap icons' do
        within('.custom-navbar') do
          expect(page).to have_css('i.bi-hdd')
          expect(page).to have_css('i.bi-file-text')
          expect(page).to have_css('i.bi-book')
          expect(page).to have_css('i.bi-people')
        end
      end

      it 'shows user menu on desktop' do
        within('.user-menu-container') do
          # User menu shows name if available, otherwise email
          expected_text = user.name || user.email
          expect(page).to have_css('.user-menu-link', text: expected_text)
        end
      end
    end

    context 'when on admin pages' do
      before do
        # Create collections so vocabularies dropdown appears in admin too
        create(:aspace_collection, name: 'Test Aspace Collection')
        create(:contentdm_collection, name: 'Test ContentDM Collection')

        sign_in user
        visit admin_users_path
      end

      it 'still displays the global navigation' do
        expect(page).to have_css('.custom-navbar')
        expect(page).to have_css('.navbar-brand', text: 'Isilon Tracker')
      end

      it 'shows users link as active' do
        within('.custom-navbar') do
          expect(page).to have_css('.nav-link.active', text: 'Users')
        end
      end
    end

    context 'vocabularies dropdown' do
      before do
        # Create collections so vocabularies dropdown appears
        create(:aspace_collection, name: 'Test Aspace Collection')
        create(:contentdm_collection, name: 'Test ContentDM Collection')

        sign_in user
        visit root_path
      end

      it 'contains links to admin collection pages' do
        # Click the vocabularies dropdown to open it
        find('.nav-link.dropdown-toggle', text: 'Vocabularies').click

        # Be more specific about which dropdown menu we're looking at
        vocabularies_dropdown = find('.nav-item', text: 'Vocabularies')
        within(vocabularies_dropdown) do
          within('.dropdown-menu') do
            expect(page).to have_link('Aspace collection', href: admin_aspace_collections_path)
            expect(page).to have_link('Contentdm collection', href: admin_contentdm_collections_path)
          end
        end
      end
    end

    context 'volumes dropdown' do
      before do
        create(:volume, name: 'Test Volume')
        sign_in user
        visit root_path
      end

      it 'contains links to all volumes and volume management' do
        # Click the volumes dropdown to open it
        find('.nav-link.dropdown-toggle', text: 'Volumes').click

        # Be more specific about which dropdown menu we're looking at
        volumes_dropdown = find('.nav-item', text: 'Volumes')
        within(volumes_dropdown) do
          within('.dropdown-menu') do
            expect(page).to have_link('All Volumes', href: volumes_path)
            expect(page).to have_link('Test Volume')
          end
        end
      end
    end
  end
end
