require 'rails_helper'

RSpec.describe CampMentorsController do
  let!(:camp_mentor) { create(:camp_mentor, camp: create(:camp), mentor: login_mentor) }

  describe 'GET index' do
    subject { get :index, { mentor_id: camp_mentor.mentor.id } }

    its(:status) { is_expected.to eq(200) }
  end

  describe 'PUT update' do
    subject { put :update, { mentor_id: camp_mentor.mentor.id, id: camp_mentor.camp.id, camp_mentor: attributes_for(:camp_mentor, comment: 'test comment') } }

    its(:status) { is_expected.to eq(302) }
    it { is_expected.to redirect_to mentor_mentor_availabilities_url }
  end

  describe 'GET show_comment' do
    subject { get :show_comment, { mentor_id: camp_mentor.mentor.id, id: camp_mentor.camp.id } }

    its(:status) { is_expected.to eq(200) }
  end

  describe 'GET edit_staff_memo' do
    subject { get :edit_staff_memo, { mentor_id: camp_mentor.mentor.id, id: camp_mentor.camp.id } }

    its(:status) { is_expected.to eq(200) }
  end

  describe 'PATCH update_staff_memo' do
    subject { patch :update_staff_memo, { mentor_id: camp_mentor.mentor.id, id: camp_mentor.id, camp_mentor: attributes_for(:camp_mentor, camp_id: camp_mentor.camp.id, staff_memo: 'test memo') } }

    its(:status) { is_expected.to eq(302) }
    it { is_expected.to redirect_to m_camp_path(camp_mentor.camp.path) }
  end
end
