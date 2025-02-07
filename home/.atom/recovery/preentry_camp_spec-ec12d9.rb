require 'rails_helper'

RSpec.describe PreentryCamp, type: :model do
  subject(:preentry_camp) do
    pc.preentry_camp_parents = [create(:preentry_camp_parent, preentry_camp: pc, parent: parent_status.parent)]
    pc
  end

  let!(:pc) { create(:preentry_camp, :with_preentried) }
  let!(:parent_status) { create(:ps_credit_paid, :with_student_status) }

  describe '#started?' do
    its(:start_date) { is_expected.to eq Date.yesterday }
    it { is_expected.to be_started }

    it 'has not started' do
      stub_date(Date.yesterday - 1.day)
      expect(preentry_camp).not_to be_started
    end
  end
  #   describe '#finished?' do
  #     its(:end_date) { is_expected.to eq Date.tomorrow }
  #     it { is_expected.not_to be_finished }
  #
  #     it 'has exceeded' do
  #       stub_date(Date.tomorrow + 1.day)
  #       expect(preentry_camp).to be_finished
  #     end
  #   end
  #
  #   describe '#in_progress?' do
  #     it { is_expected.to be_in_progress }
  #
  #     it 'has not started' do
  #       stub_date(Date.yesterday - 1.day)
  #       expect(preentry_camp).not_to be_in_progress
  #     end
  #
  #     it 'has in_progress' do
  #       stub_date(Date.tomorrow + 1.day)
  #       expect(preentry_camp).not_to be_in_progress
  #     end
  #   end
  #
  #   describe '#entry_started?' do
  #     its(:entry_start_date) { is_expected.to eq Date.tomorrow }
  #     it { is_expected.not_to be_entry_started }
  #
  #     it 'has exceeded' do
  #       stub_date(Date.tomorrow + 1.day)
  #       expect(preentry_camp).to be_entry_started
  #     end
  #   end
  #
  #   describe '#get_discount_rate' do
  #     it do
  #       expect(preentry_camp.get_discount_rate(parent)).to be preentry_camp.discount_rate
  #     end
  #
  #     it 'with preentried_parent' do
  #       expect(preentry_camp.get_discount_rate(parent)).to be preentry_camp.discount_rate
  #     end
  #   end
  #
  #   # TODO: auto-generated
  #   describe '#max_discount' do
  #     xit 'works' do
  #       preentry_camp = described_class.new
  #       parent = double('parent')
  #       result = preentry_camp.max_discount(parent)
  #       expect(result).not_to be_nil
  #     end
  #   end
  #
  #   # TODO: auto-generated
  #   describe '#discount' do
  #     xit 'works' do
  #       preentry_camp = described_class.new
  #       price = double('price')
  #       parent = double('parent')
  #       result = preentry_camp.discount(price, parent)
  #       expect(result).not_to be_nil
  #     end
  #   end
end
