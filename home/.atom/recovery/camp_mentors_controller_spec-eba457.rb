require 'rails_helper'

RSpec.describe CampMentorsController do
  subject(:camp_mentor) { build(:camp_mentor, camp: create(:camp), mentor: create(:valid_mentor)) }

  before do
    create(:mentor)
  end

  describe 'GET index' do
    it 'works' do
      get :index, { mentor_id: camp_mentor.mentor.id }
      expect(response.status).to eq(200)
    end
  end

  describe 'PUT update' do
    it 'works' do
      put :update, { mentor_id: camp_mentor.mentor.id, id: camp_mentor.camp.id }, {}
      expect(response.status).to eq(200)
    end
  end

  # TODO: auto-generated
  describe 'GET show_comment' do
    xit 'works' do
      get :show_comment, {}, {}
      expect(response.status).to eq(200)
    end
  end

  # TODO: auto-generated
  describe 'GET edit_staff_memo' do
    xit 'works' do
      get :edit_staff_memo, {}, {}
      expect(response.status).to eq(200)
    end
  end

  # TODO: auto-generated
  describe 'GET update_staff_memo' do
    xit 'works' do
      get :update_staff_memo, {}, {}
      expect(response.status).to eq(200)
    end
  end
end
