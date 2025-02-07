require 'rails_helper'
require 'bigdecimal'

RSpec.describe CampCancelRate, type: :model do
  subject do
    described_class.cancel_rate(plan, date)
  end

  let(:camp) { create(:camp) }
  let(:plan) { camp.plans[0] }

  it { expect(plan.cancel_fee_start_date).to be nil }

  describe '#cancel_rate' do
    describe 'with plan.cancel_fee_start_date' do
      let(:plan) { camp.plans[1] }
      let(:date) { plan.cancel_fee_start_date }

      it { expect(plan.cancel_fee_start_date).not_to be nil }
      it { is_expected.to eq(BigDecimal('50.00')) }

      context 'when not passed' do
        let(:date) { plan.cancel_fee_start_date - 1 }

        it { is_expected.to eq(BigDecimal('0')) }
      end
    end

    describe 'with camp.cancel_fee_start_date' do
      let(:date) { camp.cancel_fee_start_date }

      it { expect(camp.cancel_fee_start_date).not_to be nil }
      it { is_expected.to eq(BigDecimal('50.00')) }

      context 'when not passed' do
        let(:date) { camp.cancel_fee_start_date - 1 }

        it { is_expected.to eq(BigDecimal('0')) }
      end
    end

    describe 'with plan.apply_deadline' do
      let(:camp) do
        x = create(:camp)
        x.cancel_fee_start_date = nil
        x
      end
      let(:plan) do
        camp.plans[0].cancel_fee_start_date = nil
        camp.plans[0]
      end
      let(:date) { plan.apply_deadline + 1 }

      it { expect(plan.cancel_fee_start_date).to be nil }
      it { expect(camp.cancel_fee_start_date).to be nil }
      it { expect(plan.apply_deadline).not_to be nil }
      it { is_expected.to eq(BigDecimal('50.00')) }

      context 'when not passed' do
        let(:date) { plan.apply_deadline }

        it { is_expected.to eq(BigDecimal('0')) }
      end
    end

    describe 'with camp.apply_deadline' do
      let(:camp) do
        x = create(:camp)
        x.cancel_fee_start_date = nil
        x
      end
      let(:plan) { camp.plans[0] }
      let(:date) { plan.apply_deadline + 1 }

      it { expect(plan.cancel_fee_start_date).to be nil }
      it { expect(camp.cancel_fee_start_date).to be nil }
      it { expect(camp.apply_deadline).not_to be nil }
      it { is_expected.to eq(BigDecimal('50.00')) }

      context 'when not passed' do
        let(:date) { camp.apply_deadline }

        it { is_expected.to eq(BigDecimal('0')) }
      end
    end

    describe 'without any date' do
      let(:camp) do
        x = create(:camp)
        x.cancel_fee_start_date = nil
        x.apply_deadline = nil
        x
      end
      let(:plan) { camp.plans[0] }
      let(:date) { Date.today }

      it { expect(plan.cancel_fee_start_date).to be nil }
      it { expect(camp.cancel_fee_start_date).to be nil }
      it { expect(camp.apply_deadline).to be nil }
      it { is_expected.to eq(BigDecimal('100.00')) }
    end

    describe 'withoout cancel_rates' do
      let(:camp) { create(:free_camp) }
      let(:plan) { camp.plans[0] }
      let(:date) { Date.today }

      it { expect(camp.camp_cancel_rates.count).to eq(0) }
      it { is_expected.to eq(BigDecimal('0')) }
    end

    describe 'clculate cancel_rate' do
      let(:plan) { camp.plans[0] }

      it { expect(camp.camp_cancel_rates.count).not_to eq(0) }

      describe '-2' do
        let(:date) { plan.start_date - 2 }

        it { is_expected.to eq(BigDecimal('50.00')) }
      end

      describe '-1' do
        let(:date) { plan.start_date - 1 }

        it { is_expected.to eq(BigDecimal('80.00')) }
      end

      describe '0' do
        let(:date) { plan.start_date }

        it { is_expected.to eq(BigDecimal('100.00')) }
      end

      describe '+1' do
        let(:date) { plan.start_date + 1 }

        it { is_expected.to eq(BigDecimal('100.00')) }
      end
    end
  end
end
