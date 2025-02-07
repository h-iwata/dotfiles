require 'rails_helper'
require 'bigdecimal'

RSpec.describe CampCancelRate, type: :model do
  describe '#cancel_rate' do
    subject do
      described_class.cancel_rate(plan, date)
    end

    let(:camp) { create(:camp) }
    let(:free_camp) { create(:free_camp) }

    describe "with plan.cancel_fee_start_date" do
      let(:plan) { camp.plans[1] }

      it { expect(plan.cancel_fee_start_date).not_to be nil }

      context "when not passed" do
        let(:date) { plan.cancel_fee_start_date - 1 }

        it { is_expected.to eq(BigDecimal("0")) }
      end

      context "when passed" do
        let(:date) { plan.cancel_fee_start_date }

        it { is_expected.to eq(BigDecimal("50.00")) }
      end
    end

    describe "with camp.cancel_fee_start_date" do
      let(:plan) { camp.plans[0] }

      it { expect(plan.cancel_fee_start_date).to be nil }
      it { expect(camp.cancel_fee_start_date).not_to be nil }

      context "when not passed" do
        let(:date) { camp.cancel_fee_start_date - 1 }

        it { is_expected.to eq(BigDecimal("0")) }
      end

      context "when passed" do
        let(:date) { camp.cancel_fee_start_date }

        it { is_expected.to eq(BigDecimal("50.00")) }
      end
    end

    it 'plan.apply_deadline' do
      plan = camp.plans[0]
      plan.cancel_fee_start_date = nil
      camp.cancel_fee_start_date = nil
      expect(plan.cancel_fee_start_date).to be nil
      expect(plan.apply_deadline).not_to be nil
      expect(camp.cancel_fee_start_date).to be nil
      expect(described_class.cancel_rate(plan, plan.apply_deadline)).to eq(BigDecimal("0"))
      expect(described_class.cancel_rate(plan, plan.apply_deadline + 1)).not_to eq(BigDecimal("0"))
    end

    it 'only camp.apply_deadline' do
      plan = camp.plans[0]
      camp.cancel_fee_start_date = nil
      expect(plan.cancel_fee_start_date).to be nil
      expect(camp.cancel_fee_start_date).to be nil
      expect(camp.apply_deadline).not_to be nil
      expect(described_class.cancel_rate(plan, camp.apply_deadline)).to eq(BigDecimal("0"))
      expect(described_class.cancel_rate(plan, camp.apply_deadline + 1)).not_to eq(BigDecimal("0"))
    end

    it 'camp.apply_deadline is nil' do
      plan = camp.plans[0]
      camp.cancel_fee_start_date = nil
      camp.apply_deadline = nil
      expect(plan.cancel_fee_start_date).to be nil
      expect(camp.cancel_fee_start_date).to be nil
      expect(camp.apply_deadline).to be nil
      expect(described_class.cancel_rate(plan, Date.today)).not_to eq(BigDecimal("0"))
    end

    it 'clculate cancel_fee' do
      plan = camp.plans[0]
      expect(camp.camp_cancel_rates.count).not_to eq(0)
      expect(described_class.cancel_rate(plan, plan.start_date - 2)).to eq(BigDecimal("50.00"))
      expect(described_class.cancel_rate(plan, plan.start_date - 1)).to eq(BigDecimal("80.00"))
      expect(described_class.cancel_rate(plan, plan.start_date)).to eq(BigDecimal("100.00"))
      expect(described_class.cancel_rate(plan, plan.start_date + 1)).to eq(BigDecimal("100.00"))
    end

    it 'cancel fee is 0 if cancel_rate not exists' do
      plan = free_camp.plans[0]
      expect(free_camp.camp_cancel_rates.count).to eq(0)
      expect(described_class.cancel_rate(plan, Date.today)).to eq(BigDecimal("0"))
    end
  end
end
