require 'rails_helper'

RSpec.describe ParentStatus, type: :model do
  describe("#valid?") do
    subject(:parent_status) { build(:ps_bank_pending_confirmation, :with_student_status) }

    context 'invalid combination of camp and payment.' do
      before do
        parent_status.payment = Payment.find_by(option_name: 'クレジット払い（3回）') || create(:credit_card3)
      end

      it { is_expected.to be_invalid }
    end

    context 'does not allow own PCs if camp is set to all PC rental' do
      it do
        ps = create(:ps_bank_pending_confirmation, :with_student_status_cheapest)
        ps.camp.update!(is_pc_all_rental: true)
        expect(ps).to be_invalid
        expect(ps).to have(1).errors_on(:base)
      end
    end

    context 'when parent_status.destroy' do
      it 'deletes all student_statuses' do
        ss = parent_status.student_statuses.map { |a| a }
        parent_status.destroy
        expect(described_class.all).not_to include(parent_status)
        expect(StudentStatus.all).not_to include(ss)
      end
    end
  end

  describe("#payment_due_date") do
    subject(:parent_status) { create(:ps_bank_pending_payment) }

    context "automatically set" do
      it do
        stub_today('2015-12-15')
        expect(parent_status.payment_due_date).to eq(Date.parse('2015-12-15') + parent_status.camp.payment_due_days)
      end
    end
  end

  context 'search by name, email, phone' do
    before do
      @parent = create(:parent,
                       first_name: 'komori',
                       last_name: 'shimpei',
                       first_name_kana: 'コモリ',
                       last_name_kana: 'シンペイ')
      @student = create(:student,
                        first_name: 'komori',
                        last_name: 'sisopei',
                        first_name_kana: 'コモリ',
                        last_name_kana: 'シソペイ',
                        parent_id: @parent.id)

      ps = build(:ps_bank_pending_confirmation, :with_student_status_cheapest)
      ps.parent = @parent
      ps.student_statuses.first.student = @student
      ps.save
    end

    def search_parent_statuses(query)
      ParentStatus.search(by_name_or_email_or_phone: query).result
    end

    it 'hits with blank words' do
      expect(search_parent_statuses('').count).to eq(1)
    end

    it 'hits including parent_name' do
      expect(search_parent_statuses('shimpei').count).to eq(1)
    end

    it 'hits including student_name' do
      expect(search_parent_statuses('sisopei').count).to eq(1)
    end

    it 'does not hit including mismatch words' do
      expect(search_parent_statuses('komosama shimpei').count).to eq(0)
    end
  end

  it 'valids camp coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, name: 'coupon', code: 'code', camp: ps.camp)

    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 1
    expect(ps.coupons_are_valid?(true)).to be true
    expect(ps.errors.count).to eq 0
    expect(ps.coupons_are_valid?(false)).to be true
  end

  it 'valids non camp coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, name: 'coupon', code: 'code', camp: nil)

    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 1
    expect(ps.coupons_are_valid?(true)).to be true
    expect(ps.errors.count).to eq 0
    expect(ps.coupons_are_valid?(false)).to be true
  end

  it 'invalids inactive coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, :inactive, name: 'coupon', code: 'code', camp: nil)

    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 1

    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.errors.count).to eq 1
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')

    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'invalids duplicate coupon code' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, name: 'coupon', code: 'code', camp: nil)

    ps.coupons.push(coupon)
    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 2

    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.errors.count).to eq 1
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.duplicate_coupons'))
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.duplicate_coupons')

    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'invalids other camp coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, name: 'coupon', code: 'code', camp: create(:camp, path: 'summer2014'))

    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 1

    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.errors.count).to eq 1
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')

    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'invalids school_only coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil)

    ps.coupons.push(coupon)
    expect(ps.coupons.length).to eq 1

    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.errors.count).to eq 1
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')

    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'invalids already used coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil)
    ps.parent.used_coupons.push(coupon)
    ps.parent.save!

    parent = Parent.find(ps.parent.id)
    expect(parent.used_coupons.count).to be > 0

    ps.coupons.push(coupon)
    expect(ps.send(:already_used_coupons).length).to eq 1
    expect(ps.send(:coupons_are_already_used?)).to be true
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_already_used'))
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_already_used')
  end

  it 'invalids own coupon' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil, parent: ps.parent)

    ps.coupons.push(coupon)
    expect(ps.send(:using_own_coupon).length).to eq 1
    expect(ps.send(:own_coupons_are_used?)).to be true
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.cannot_use_own_coupon'))
    expect(ps.coupon_errors.count).to eq 1
    expect(ps.coupon_errors[coupon.code].count).to eq 1
    expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.cannot_use_own_coupon')
  end

  it 'invalids two new comer coupons' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    coupon = create(:base_coupon, name: 'coupon', code: 'code', camp: nil)
    new_coupon1 = create(:base_coupon, :new_comers, name: 'coupon1', code: 'code1', camp: ps.camp)
    new_coupon2 = create(:base_coupon, :new_comers, name: 'coupon2', code: 'code2', camp: nil)

    ps.coupons.push(coupon)

    # add first new comer coupon
    ps.coupons.push(new_coupon1)
    expect(ps.coupons.length).to eq 2
    expect(ps.send(:new_comer_coupons).length).to eq 1
    expect(ps.send(:multiple_new_comers_are_used?)).to be false
    expect(ps.coupons_are_valid?(true)).to be true
    expect(ps.coupons_are_valid?(false)).to be true

    # add second new comer coupon
    ps.coupons.push(new_coupon2)
    expect(ps.coupons.length).to eq 3
    expect(ps.send(:new_comer_coupons).length).to eq 2
    expect(ps.send(:multiple_new_comers_are_used?)).to be true
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.duplicate_new_comer_coupons'))
    expect(ps.coupon_errors.count).to eq 2
    expect(ps.coupon_errors[new_coupon1.code].count).to eq 1
    expect(ps.coupon_errors[new_coupon1.code][0]).to eq I18n.t('errors.messages.duplicate_new_comer_coupons')
    expect(ps.coupon_errors[new_coupon2.code].count).to eq 1
    expect(ps.coupon_errors[new_coupon2.code][0]).to eq I18n.t('errors.messages.duplicate_new_comer_coupons')
    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'invalids two exclusive coupons' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    # create coupons (not exclusive)
    coupon1 = create(:base_coupon, name: 'coupon1', code: 'code1', camp: ps.camp)
    coupon2 = create(:base_coupon, name: 'coupon2', code: 'code2', camp: nil)
    # create exclusive coupons
    ex_coupon1 = create(:exclusive_coupon, camp: ps.camp)
    ex_coupon2 = create(:exclusive_coupon, camp: nil)

    # add coupons
    ps.coupons.push(coupon1)
    ps.coupons.push(coupon2)
    expect(ps.coupons.length).to eq 2
    expect(ps.send(:multiple_exclusive_are_used?)).to be false
    expect(ps.coupons_are_valid?(true)).to be true
    expect(ps.coupons_are_valid?(false)).to be true

    # add first exclusive coupon
    ps.coupons.push(ex_coupon1)
    expect(ps.coupons.length).to eq 3
    expect(ps.send(:multiple_exclusive_are_used?)).to be false
    expect(ps.coupons_are_valid?(true)).to be true
    expect(ps.coupons_are_valid?(false)).to be true

    # add second exclusive coupon
    ps.coupons.push(ex_coupon2)
    expect(ps.coupons.length).to eq 4
    expect(ps.send(:multiple_exclusive_are_used?)).to be true
    ex_codes = [ex_coupon1.code, ex_coupon2.code].join(',')
    expect(ps.errors.full_messages).to include(I18n.t('errors.messages.duplicate_exclusive_coupons', coupons: ex_codes))
    expect(ps.coupon_errors.count).to eq 2
    expect(ps.coupon_errors[ex_coupon1.code].count).to eq 1
    expect(ps.coupon_errors[ex_coupon1.code][0]).to eq I18n.t('errors.messages.duplicate_exclusive_coupons', coupons: ex_codes)
    expect(ps.coupon_errors[ex_coupon2.code].count).to eq 1
    expect(ps.coupon_errors[ex_coupon2.code][0]).to eq I18n.t('errors.messages.duplicate_exclusive_coupons', coupons: ex_codes)
    expect(ps.coupons_are_valid?(true)).to be false
    expect(ps.coupons_are_valid?(false)).to be false
  end

  it 'onlies include created coupons after replace_with_db_coupons called' do
    ps = build(:ps_bank_pending_confirmation, :with_student_status)
    expect(ps).to be_valid

    # create coupons (not exclusive)
    coupon1 = create(:base_coupon, name: 'coupon1', code: 'code1', camp: ps.camp)
    coupon2 = create(:base_coupon, name: 'coupon2', code: 'code2', camp: nil)
    coupon3 = build(:base_coupon, name: 'coupon3', code: 'code3', camp: nil)

    ps.coupons.push(coupon1)
    ps.coupons.push(coupon2)
    ps.coupons.push(coupon3)
    expect(ps.coupons.length).to eq 3

    ps.replace_with_db_coupons
    expect(ps.coupons.length).to eq 2
    code_list = ps.coupons.map(&:code)
    expect(code_list.include? coupon1.code).to be true
    expect(code_list.include? coupon2.code).to be true
    expect(code_list.include? coupon3.code).to be false
  end

  describe 'calculate_price' do
    it 'cancel one without cancel_fee' do
      # 新規申し込み
      ps = create(:ps_credit_paid_points_used, :with_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 39050,
        "tax" => 3550,
        "price_before_tax" => 35500,
        "total_price" => 39500,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => ps.student_statuses[0].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.invoices.last.details_hash).to eq(expected)

      # 変更期限内、キャンセル料なし
      stub_today("2014-03-11")
      stub_now("2014-03-11 00:00:00")
      expect(GMOPayment).to receive(:cancel_payment).with(
        kind_of(PaymentTransaction)
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 0,
        "tax" => 0,
        "price_before_tax" => 0,
        "total_price" => 0,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => "2014-03-11T00:00:00.000+09:00", } },
      }
      expect(ps.invoices.last.details_hash).to eq(expected)
    end

    it 'cancel one with cancel_fee' do
      # 新規申し込み
      ps = create(:ps_credit_paid_points_used, :with_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 39050,
        "tax" => 3550,
        "price_before_tax" => 35500,
        "total_price" => 39500,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => ps.student_statuses[0].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.invoices.last.details_hash).to eq(expected)

      # 開始日の前日キャンセル 80%のキャンセル料
      stub_today("2014-03-24")
      stub_now("2014-03-24 00:00:00")
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 31240
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 31240,
        "tax" => 2840,
        "price_before_tax" => 28400,
        "total_price" => 28400,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 28400,
                     "cancel_rate" => 80,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", } },
      }
      expect(ps.invoices.last.details_hash).to eq(expected)
    end

    it 'cancel three without cancel_fee' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 189750,
        "tax" => 17250,
        "price_before_tax" => 172500,
        "total_price" => 182500,
        "total_discount" => -10000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -6000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => ps.student_statuses[0].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[1].id}" =>
                     { "status" => ps.student_statuses[1].status,
                       "total" => 39500,
                       "price" => 34500,
                       "pc_rental_fee" => 5000,
                       "rental_prices" => { "total_price" => 0, "rentals" => [] },
                       "early_discount" => 0,
                       "travel_cost" => 0,
                       "student_name" => ps.student_statuses[1].student.name,
                       "cancel_fee" => 0,
                       "cancel_rate" => 0,
                       "cancelled_at" => nil,  },
                "#{ps.student_statuses[2].id}" =>
                     { "status" => ps.student_statuses[2].status,
                       "total" => 103500,
                       "price" => 98500,
                       "pc_rental_fee" => 5000,
                       "rental_prices" => { "total_price" => 0, "rentals" => [] },
                       "early_discount" => 0,
                       "travel_cost" => 0,
                       "student_name" => ps.student_statuses[2].student.name,
                       "cancel_fee" => 0,
                       "cancel_rate" => 0,
                       "cancelled_at" => nil, } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # 変更期限内、キャンセル料なし
      stub_today("2014-03-11")
      stub_now("2014-03-11 00:00:00")
      expect(GMOPayment).to receive(:cancel_payment).with(
        kind_of(PaymentTransaction)
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 0,
        "tax" => 0,
        "price_before_tax" => 0,
        "total_price" => 0,
        "total_discount" => -10000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -6000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => "2014-03-11T00:00:00.000+09:00", },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => "2014-03-11T00:00:00.000+09:00", },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => "cancelled",
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => "2014-03-11T00:00:00.000+09:00", } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end

    it 'cancel three with cancel_fee' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 189750,
        "tax" => 17250,
        "price_before_tax" => 172500,
        "total_price" => 182500,
        "total_discount" => -10000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -6000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => ps.student_statuses[0].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => ps.student_statuses[1].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => ps.student_statuses[2].status,
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today("2014-03-24")
      stub_now("2014-03-24 00:00:00")
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 106808
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 106808,
        "tax" => 9709,
        "price_before_tax" => 97099,
        "total_price" => 97099,
        "total_discount" => -10000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -6000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 28933,
                     "cancel_rate" => 80,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 18083,
                     "cancel_rate" => 50,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => "cancelled",
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 50083,
                     "cancel_rate" => 50,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end

    it 'cancel three with cancel_fee one by one' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 189750,
        "tax" => 17250,
        "price_before_tax" => 172500,
        "total_price" => 182500,
        "total_discount" => -10000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -6000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => ps.student_statuses[0].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => ps.student_statuses[1].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => ps.student_statuses[2].status,
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today("2014-03-24")
      stub_now("2014-03-24 00:00:00")
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 181500
      ).and_return(nil)
      ps.cancel_student_status(ps.student_statuses[0].id)
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 181500,
        "tax" => 16500,
        "price_before_tax" => 165000,
        "total_price" => 173000,
        "total_discount" => -8000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => -4000,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 30000,
                     "cancel_rate" => 80,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => ps.student_statuses[1].status,
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => ps.student_statuses[2].status,
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today("2014-03-24")
      stub_now("2014-03-24 00:00:00")
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 163075
      ).and_return(nil)
      ps.cancel_student_status(ps.student_statuses[1].id)
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 163075,
        "tax" => 14825,
        "price_before_tax" => 148250,
        "total_price" => 152250,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 30000,
                     "cancel_rate" => 80,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 18750,
                     "cancel_rate" => 50,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => ps.student_statuses[2].status,
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 0,
                     "cancel_rate" => 0,
                     "cancelled_at" => nil, } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today("2014-03-24")
      stub_now("2014-03-24 00:00:00")
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 108350
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        "price" => 108350,
        "tax" => 9850,
        "price_before_tax" => 98500,
        "total_price" => 98500,
        "total_discount" => -4000,
        "payment_discount" => 0,
        "coupon_discount" => 0,
        "introduction_coupon_discount" => 0,
        "points_used" => -4000,
        "sibling_discount" => 0,
        "ss_prices" =>
              { "#{ps.student_statuses[0].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[0].student.name,
                     "cancel_fee" => 30000,
                     "cancel_rate" => 80,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[1].id}" =>
                   { "status" => "cancelled",
                     "total" => 39500,
                     "price" => 34500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[1].student.name,
                     "cancel_fee" => 18750,
                     "cancel_rate" => 50,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", },
                "#{ps.student_statuses[2].id}" =>
                   { "status" => "cancelled",
                     "total" => 103500,
                     "price" => 98500,
                     "pc_rental_fee" => 5000,
                     "rental_prices" => { "total_price" => 0, "rentals" => [] },
                     "early_discount" => 0,
                     "travel_cost" => 0,
                     "student_name" => ps.student_statuses[2].student.name,
                     "cancel_fee" => 49750,
                     "cancel_rate" => 50,
                     "cancelled_at" => "2014-03-24T00:00:00.000+09:00", } },
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end
  end
end
