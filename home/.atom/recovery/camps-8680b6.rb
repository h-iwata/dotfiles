FactoryGirl.define do
  factory :camp do
    name { 'Spring 2014' }
    apply_deadline { Date.new(2014, 3, 11) }
    details_url { AppConfig.urls.lit_web + '/spring_camp2014' }
    coupon_prefix { '1403' }
    path { 'spring2014' }
    pc_rental_fee { 5000 }
    logo_filename { 'summer_camp_2014.jpg' }
    terms_of_service { '申込約款' }
    apply_sibling_discount { true }
    payment_due_days { 14 }
    allow_coupon_and_points { true }
    cancel_fee_start_date { Date.new(2014, 3, 12) }

    after(:build, :create) do |camp|
      camp.plans = [create(:plan_keio),
                    create(:plan_todai),
                    create(:plan_todai_inactive)]
      camp.bank_account = create(:bank_account)
      camp.payments << [create(:bank), create(:credit_card)]
      camp.camp_cancel_rates << [
        create(:camp_cancel_rate_30),
        create(:camp_cancel_rate_15),
        create(:camp_cancel_rate_2),
        create(:camp_cancel_rate_1)
      ]
    end
  end
  factory :free_camp, class: 'Camp' do
    name { 'Summer 2014 SAP' }
    apply_deadline { Date.new(2014, 6, 18) }
    details_url { AppConfig.urls.lit_web + '/spring_camp2014' }
    coupon_prefix { nil }
    path { 'summer2014sap' }
    pc_rental_fee { 0 }
    logo_filename { 'summer_camp_2014.jpg' }
    terms_of_service { '申込約款' }
    is_free { true }

    after(:build) do |camp|
      camp.plans = [create(:plan_keio_sap)]
      camp.bank_account = create(:bank_account)
      camp.payments << [create(:bank), create(:credit_card)]
    end
  end
  factory :spring_2015, class: 'Camp' do
    name { 'Spring 2015' }
    apply_deadline { Date.new(2015, 3, 9) }
    details_url { AppConfig.urls.lit_web + '/camp' }
    coupon_prefix { '1503' }
    path { 'spring2015' }
    pc_rental_fee { 5000 }
    logo_filename { 'spring_camp_2015.png' }
    terms_of_service { '申込約款' }
    is_free { false }
    allow_coupon_and_points { true }

    after(:build) do |camp|
      camp.plans = [
        FactoryGirl.create(:plan_todai_spring2015),
        FactoryGirl.create(:plan_todai_spring2015_2)
      ]
      camp.bank_account = create(:bank_account)
      camp.payments << [create(:bank_smbc), create(:credit_card),
                        create(:credit_card3)]
    end
  end

  factory :sqen2015_camp, class: 'Camp' do
    name { 'SQUARE ENIX GAME CAMP 2015' }
    path { 'squareenix2015' }
    pc_rental_fee { 3000 }
    is_free { true }

    after(:build) do |camp|
      camp.plans = [create(:sqen2015_plan)]
      camp.bank_account = create(:bank_account)
      camp.payments << [create(:bank)]
    end
  end

  factory :summer2015, class: 'Camp' do
    name { 'サマーキャンプ 2015' }
    apply_deadline { Date.new(2015, 7, 6) }
    path { 'summer2015' }
    pc_rental_fee { 5000 }
    logo_filename { 'summer_camp_2015.png' }
    terms_of_service { '申込約款' }
    allow_coupon_and_points { true }

    after(:build) do |camp|
      camp.plans = [
        FactoryGirl.create(:plan_todai_summer2015),
        FactoryGirl.create(:plan_summer2015_pending_cancel)
      ]
      camp.bank_account = FactoryGirl.create(:bank_account)
      camp.payments << [create(:bank_smbc), create(:credit_card),
                        create(:credit_card3)]
    end
  end

  factory :free_camp_charge_stay, class: 'Camp' do
    name { 'キャンプ無料宿泊有料' }
    apply_deadline { Date.new(2016, 7, 31) }
    coupon_prefix { nil }
    path { 'summer2016free' }
    pc_rental_fee { 5000 }
    logo_filename { 'spring_camp_2015.png' }
    terms_of_service { '申込約款' }
    apply_sibling_discount { false }
    allow_coupon_and_points { false }

    after(:build) do |camp|
      camp.plans = [
        FactoryGirl.create(:plan_summer2016_free_charge_stay),
        FactoryGirl.create(:plan_summer2015_pending_cancel)
      ]
      camp.bank_account = FactoryGirl.create(:bank_account)
      camp.payments << [create(:bank_smbc), create(:credit_card),
                        create(:credit_card3)]
    end
  end
end
