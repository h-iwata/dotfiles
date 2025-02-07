require 'rails_helper'

RSpec.describe PlansController do
  let(:camp) { create(:camp) }

  before { login_admin }

  describe 'GET courses' do
    it 'works' do
      post :courses, { id: camp.plans.first.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET plan_courses' do
    it 'works' do
      get :plan_courses, { id: camp.plans.first.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'GET stayplans' do
    it 'works' do
      get :stayplans, { id: camp.plans.first.id }
      expect(response.status).to eq(200)
    end
  end
end
