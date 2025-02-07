FactoryGirl.define do
  factory :preentry_camp do
    discount_rate { 5 }
    target_camp_joined_discount_rate { 8 }
    start_date { Date.yesterday }
    end_date { Date.tomorrow }
    entry_start_date { Date.tomorrow }
    association :camp, factory: :spring_2015

    trait :with_preentried do
      after(:create) do |preentry_camp|
        ps = create(:base_parent_status, :with_camp, :with_student_status, ss: paid)
        preentry_camp.preentry_camp_parents = [create(:preentry_camp_parent, preentry_camp: preentry_camp, parent: ps.parent)]
        preentry_camp.preentry_target_camps = [create(:preentry_target_camp, preentry_camp: preentry_camp, camp: find_or_create(:camp))]
      end
    end
  end
end
