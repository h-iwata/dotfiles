FactoryGirl.define do
  factory :preentry_camp do
    discount_rate { 5 }
    target_camp_joined_discount_rate { 8 }
    start_date { Date.yesterday }
    end_date { Date.tomorrow }
    entry_start_date { Date.tomorrow }
    association :camp, factory: :camp
    trait :with_preentried do
      after(:create) do |preentry_camp|
        ps = create(:ps_bank_paid, :with_summer2015_camp, :with_parent, :with_student_status, :with_invoice)
        preentry_camp.preentry_camp_parents = [create(:preentry_camp_parent, preentry_camp: preentry_camp, ps.parent)]
        preentry_camp.preentry_target_camps = [create(:preentry_target_camp, preentry_camp: preentry_camp, camp: create(:summer2015))]
      end
    end
  end
end
