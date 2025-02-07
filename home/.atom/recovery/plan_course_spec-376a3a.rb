require 'rails_helper'

RSpec.describe PlanCourse, type: :model do
  subject(:plan_course) { build(:plan_course, plan: plan, course: iphone, capacity: 20) }

  let(:plan)          { build(:plan, capacity: 100) }
  let(:iphone)        { build(:iphone) }

  describe '#capacity_status' do
    context 'without threshold parameter' do
      it do
        allow(plan_course).to receive(:current_count).and_return(20)
        expect(plan_course.capacity_status).to eq(:full)
        allow(plan_course).to receive(:current_count).and_return(18)
        expect(plan_course.capacity_status).to eq(:limited)
        allow(plan_course).to receive(:current_count).and_return(16)
        expect(plan_course.capacity_status).to eq(:limited)
        allow(plan_course).to receive(:current_count).and_return(15)
        expect(plan_course.capacity_status).to eq(:available)
      end
    end

    it 'with threshold parameter' do
      plan.fullied_threshold = 90
      plan.limited_threshold = 75
      plan.save
      allow(plan_course).to receive(:current_count).and_return(18)
      expect(plan_course.capacity_status).to eq(:full)
      allow(plan_course).to receive(:current_count).and_return(17)
      expect(plan_course.capacity_status).to eq(:limited)
      allow(plan_course).to receive(:current_count).and_return(15)
      expect(plan_course.capacity_status).to eq(:limited)
      allow(plan_course).to receive(:current_count).and_return(14)
      expect(plan_course.capacity_status).to eq(:available)
    end
  end
end
