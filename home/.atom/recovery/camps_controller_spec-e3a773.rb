require 'rails_helper'

RSpec.describe CampsController do
  let(:camp) { find_or_create(:camp, :name) }
  let(:iphone) { find_or_create(:iphone, :name) }
  let(:plan_keio) { find_or_create(:plan_keio, :name) }

  before do
    create(:ps_bank_pending_confirmation, :with_student_status_cheapest)
  end

  describe 'GET plans_for_location' do
    it 'works' do
      get :plans_for_location, { id: camp.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET guide_preview' do
    it 'works' do
      login_admin
      get :guide_preview, { id: camp.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET count' do
    it 'works' do
      login_admin
      get :count, { id: camp.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET rentals' do
    it 'works' do
      get :rentals, { id: camp.id, course_id: iphone.id, plan_id: plan_keio.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET give_introduction_points' do
    it 'works' do
      login_admin
      tomorrow = Time.zone.tomorrow
      get :give_introduction_points, { camp_ids: [camp.id], parent_points: {
        'expire_at(1i)': tomorrow.year,
        'expire_at(2i)': tomorrow.month,
        'expire_at(3i)': tomorrow.day,
        'expire_at(4i)': "00",
        'expire_at(5i)': "00",
      } }
      expect(response.status).to eq(302)
      expect(response).to redirect_to admin_camps_path
    end
  end

  describe 'POST read_sheet' do
    it 'works' do
      login_admin
      post :read_sheet, { sheet_url: 'https://docs.google.com/spreadsheets/d/1BHybz45pesNFhW6iWhNHyzW4_SDc323EbXGHV0cUPnI/edit#gid=1544038291', save: false }
      pp response
      expect(response.status).to eq(200)
    end
  end
end
