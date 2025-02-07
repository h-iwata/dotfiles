require 'rails_helper'

RSpec.describe CreditsController do
  let(:parent) { create(:parent, stripe_customer: :stripe_customer) }

  before { login_parent }

  describe 'GET index' do
    it 'works' do
      get :index, {}, {}
      expect(response.status).to eq(200)
    end
  end

  describe 'GET new' do
    it 'works' do
      get :new, {}, {}
      expect(response.status).to eq(200)
    end
  end

  describe 'GET select' do
    it 'works' do
      get :select, { card: { id: parent.stripe_customer.stripe_id } }, {}
      expect(response.status).to eq(200)
    end
  end

  describe 'POST create' do
    xit 'works' do
      post :create, {}, {}
      expect(response.status).to eq(200)
    end
  end

  describe 'DELETE destroy' do
    xit 'works' do
      delete :destroy, {}, {}
      expect(response.status).to eq(200)
    end
  end
end
