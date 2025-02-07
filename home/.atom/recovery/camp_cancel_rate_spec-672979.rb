require 'rails_helper'
require 'bigdecimal'

RSpec.describe CampCancelRate, type: :model do
  subject do
    described_class.cancel_rate(plan, date)
  end

  let(:camp) { create(:camp) }
  let(:free_camp) { create(:free_camp) }

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
      let(:plan) { camp.plans[0] }
      let(:date) { camp.cancel_fee_start_date }

      it { expect(plan.cancel_fee_start_date).to be nil }
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

    it 'clculate cancel_fee' do
      plan = camp.plans[0]
      expect(camp.camp_cancel_rates.count).not_to eq(0)
      expect(described_class.cancel_rate(plan, plan.start_date - 2)).to eq(BigDecimal('50.00'))
      expect(described_class.cancel_rate(plan, plan.start_date - 1)).to eq(BigDecimal('80.00'))
      expect(described_class.cancel_rate(plan, plan.start_date)).to eq(BigDecimal('100.00'))
      expect(described_class.cancel_rate(plan, plan.start_date + 1)).to eq(BigDecimal('100.00'))
    end

    it 'cancel fee is 0 if cancel_rate not exists' do
      plan = free_camp.plans[0]
      expect(free_camp.camp_cancel_rates.count).to eq(0)
      expect(described_class.cancel_rate(plan, Date.today)).to eq(BigDecimal('0'))
    end
  end
end
