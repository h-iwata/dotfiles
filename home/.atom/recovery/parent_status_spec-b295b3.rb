require 'rails_helper'

RSpec.describe ParentStatus, type: :model do
  describe('#valid?') do
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
      let(:ss) { parent_status.student_statuses.map { |a| a } }

      before do
        parent_status.destroy
      end

      it 'deletes all student_statuses' do
        expect(described_class.all).not_to include(parent_status)
        expect(StudentStatus.all).not_to include(ss)
      end
    end
  end

  describe('#payment_due_date') do
    subject(:parent_status) { create(:ps_bank_pending_payment) }

    before do
      stub_today('2015-12-15')
    end

    context 'automatically set' do
      its(:payment_due_date) { is_expected.to eq(Date.parse('2015-12-15') + parent_status.camp.payment_due_days) }
    end
  end

  describe '#search' do
    subject { ->(query) { described_class.search(by_name_or_email_or_phone: query).result.count } }

    let(:parent) do
      create(:parent,
             first_name: 'komori',
             last_name: 'shimpei',
             first_name_kana: 'コモリ',
             last_name_kana: 'シンペイ')
    end
    let(:student) do
      create(:student,
             first_name: 'komori',
             last_name: 'sisopei',
             first_name_kana: 'コモリ',
             last_name_kana: 'シソペイ',
             parent_id: parent.id)
    end
    let(:parent_status) { build(:ps_bank_pending_confirmation, :with_student_status_cheapest) }

    before do
      parent_status.parent = parent
      parent_status.student_statuses.first.student = student
      parent_status.save
    end

    its(['']) { is_expected.to eq(1) }
    its(['shimpei']) { is_expected.to eq(1) }
    its(['sisopei']) { is_expected.to eq(1) }
    its(['komosama shimpei']) { is_expected.to eq(0) }
  end

  describe '#coupons' do
    subject(:ps) { build(:ps_bank_pending_confirmation, :with_student_status) }

    before { ps.coupons.push(coupon) }

    context 'with camp coupon' do
      let(:coupon) { create(:base_coupon, name: 'coupon', code: 'code', camp: ps.camp) }

      its(:coupons) { is_expected.to have(1).items }
      its(:errors) { is_expected.to be_empty }

      it do
        expect(ps.coupons_are_valid?(true)).to be true
        expect(ps.coupons_are_valid?(false)).to be true
      end
    end

    context 'with non camp coupon' do
      let(:coupon) { create(:base_coupon, name: 'coupon', code: 'code', camp: nil) }

      its(:coupons) { is_expected.to have(1).items }
      its(:errors) { is_expected.to be_empty }

      it do
        expect(ps.coupons_are_valid?(true)).to be true
        expect(ps.coupons_are_valid?(false)).to be true
      end
    end

    context 'with inactive coupon' do
      let(:coupon) { create(:base_coupon, :inactive, name: 'coupon', code: 'code', camp: nil) }

      its(:coupons) { is_expected.to have(1).items }

      it do
        expect(ps.coupons_are_valid?(true)).to be false
        expect(ps.errors.count).to eq 1
        expect(ps.coupons_are_valid?(false)).to be false
        expect(ps.errors.count).to eq 2
        expect(ps.coupon_errors[coupon.code]).to have(1).items
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
      end
    end

    context 'with duplicate coupon code' do
      let(:coupon) { create(:base_coupon, name: 'coupon', code: 'code', camp: nil) }

      before { ps.coupons.push(coupon) }

      its(:coupons) { is_expected.to have(2).items }

      it do
        expect(ps.coupons_are_valid?(true)).to be false
        expect(ps.errors.count).to eq 1
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.duplicate_coupons'))
        expect(ps.coupon_errors[coupon.code].count).to eq 1
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.duplicate_coupons')
        expect(ps.coupons_are_valid?(false)).to be false
      end
    end

    context 'with other camp coupon' do
      let(:coupon) { create(:base_coupon, name: 'coupon', code: 'code', camp: create(:camp, path: 'summer2014')) }

      it do
        expect(ps.coupons_are_valid?(true)).to be false
        expect(ps.errors.count).to eq 1
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
        expect(ps.coupon_errors[coupon.code].count).to eq 1
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')
        expect(ps.coupons_are_valid?(false)).to be false
      end
    end

    context 'with school_only coupon' do
      let(:coupon) { create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil) }

      it do
        expect(ps.coupons.length).to eq 1
        expect(ps.coupons_are_valid?(true)).to be false
        expect(ps.errors.count).to eq 1
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_invalid'))
        expect(ps.coupon_errors[coupon.code].count).to eq 1
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_invalid')
        expect(ps.coupons_are_valid?(false)).to be false
      end
    end

    context 'with already used coupon' do
      let(:coupon) { create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil) }

      before do
        ps.parent.used_coupons.push(coupon)
        ps.parent.save!
      end

      it do
        expect(ps.parent.used_coupons.count).to be > 0
        expect(ps.send(:already_used_coupons).length).to eq 1
        expect(ps.send(:coupons_are_already_used?)).to be true
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.coupon_already_used'))
        expect(ps.coupon_errors[coupon.code].count).to eq 1
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.coupon_already_used')
      end
    end

    context 'with own coupon' do
      let(:coupon) { create(:base_coupon, :for_school, name: 'coupon', code: 'code', camp: nil, parent: ps.parent) }

      it do
        expect(ps.send(:using_own_coupon).length).to eq 1
        expect(ps.send(:own_coupons_are_used?)).to be true
        expect(ps.errors.full_messages).to include(I18n.t('errors.messages.cannot_use_own_coupon'))
        expect(ps.coupon_errors.count).to eq 1
        expect(ps.coupon_errors[coupon.code].count).to eq 1
        expect(ps.coupon_errors[coupon.code][0]).to eq I18n.t('errors.messages.cannot_use_own_coupon')
      end
    end

    context 'with two new comer coupons' do
      let(:coupon) { create(:base_coupon, name: 'coupon', code: 'code', camp: nil) }
      let(:new_coupon1) { create(:base_coupon, :new_comers, name: 'coupon1', code: 'code1', camp: ps.camp) }
      let(:new_coupon2) { create(:base_coupon, :new_comers, name: 'coupon2', code: 'code2', camp: nil) }

      it do
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
    end

    context 'with two exclusive coupons' do
      # create coupons (not exclusive)
      let(:coupon) { create(:base_coupon, name: 'coupon1', code: 'code1', camp: ps.camp) }
      let(:coupon2) { create(:base_coupon, name: 'coupon2', code: 'code2', camp: nil) }
      # create exclusive coupons
      let(:ex_coupon1) { create(:exclusive_coupon, camp: ps.camp) }
      let(:ex_coupon2) { create(:exclusive_coupon, camp: nil) }

      it do
        # add coupons
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
    end

    describe '#replace_with_db_coupons' do
      let(:coupon) { create(:base_coupon, name: 'coupon1', code: 'code1', camp: ps.camp) }

      it do
        # create coupons (not exclusive)
        coupon2 = create(:base_coupon, name: 'coupon2', code: 'code2', camp: nil)
        coupon3 = build(:base_coupon, name: 'coupon3', code: 'code3', camp: nil)
        ps.coupons.push(coupon2)
        ps.coupons.push(coupon3)
        expect(ps.coupons.length).to eq 3
        ps.replace_with_db_coupons
        expect(ps.coupons.length).to eq 2
        code_list = ps.coupons.map(&:code)
        expect(code_list.include?(coupon.code)).to be true
        expect(code_list.include?(coupon2.code)).to be true
        expect(code_list.include?(coupon3.code)).to be false
      end
    end
  end

  describe 'calculate_price' do
    it 'cancel one without cancel_fee' do
      # 新規申し込み
      ps = create(:ps_credit_paid_points_used, :with_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 39_050,
        'tax' => 3550,
        'price_before_tax' => 35_500,
        'total_price' => 39_500,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[0].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.invoices.last.details_hash).to eq(expected)

      # 変更期限内、キャンセル料なし
      stub_today('2014-03-11')
      stub_now('2014-03-11 00:00:00')
      expect(GMOPayment).to receive(:cancel_payment).with(
        kind_of(PaymentTransaction)
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 0,
        'tax' => 0,
        'price_before_tax' => 0,
        'total_price' => 0,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => '2014-03-11T00:00:00.000+09:00'
                   } }
      }
      expect(ps.invoices.last.details_hash).to eq(expected)
    end

    it 'cancel one with cancel_fee' do
      # 新規申し込み
      ps = create(:ps_credit_paid_points_used, :with_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 39_050,
        'tax' => 3550,
        'price_before_tax' => 35_500,
        'total_price' => 39_500,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[0].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.invoices.last.details_hash).to eq(expected)

      # 開始日の前日キャンセル 80%のキャンセル料
      stub_today('2014-03-24')
      stub_now('2014-03-24 00:00:00')
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 31_240
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 31_240,
        'tax' => 2840,
        'price_before_tax' => 28_400,
        'total_price' => 28_400,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 28_400,
                     'cancel_rate' => 80,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   } }
      }
      expect(ps.invoices.last.details_hash).to eq(expected)
    end

    it 'cancel three without cancel_fee' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 189_750,
        'tax' => 17_250,
        'price_before_tax' => 172_500,
        'total_price' => 182_500,
        'total_discount' => -10_000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -6000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[0].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[1].id.to_s =>
                     {
                       'preentry_discount' => 0,
                       'status' => ps.student_statuses[1].status,
                       'total' => 39_500,
                       'price' => 34_500,
                       'pc_rental_fee' => 5000,
                       'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                       'early_discount' => 0,
                       'travel_cost' => 0,
                       'student_name' => ps.student_statuses[1].student.name,
                       'cancel_fee' => 0,
                       'cancel_rate' => 0,
                       'cancelled_at' => nil
                     },
                ps.student_statuses[2].id.to_s =>
                     {
                       'preentry_discount' => 0,
                       'status' => ps.student_statuses[2].status,
                       'total' => 103_500,
                       'price' => 98_500,
                       'pc_rental_fee' => 5000,
                       'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                       'early_discount' => 0,
                       'travel_cost' => 0,
                       'student_name' => ps.student_statuses[2].student.name,
                       'cancel_fee' => 0,
                       'cancel_rate' => 0,
                       'cancelled_at' => nil
                     } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # 変更期限内、キャンセル料なし
      stub_today('2014-03-11')
      stub_now('2014-03-11 00:00:00')
      expect(GMOPayment).to receive(:cancel_payment).with(
        kind_of(PaymentTransaction)
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 0,
        'tax' => 0,
        'price_before_tax' => 0,
        'total_price' => 0,
        'total_discount' => -10_000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -6000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => '2014-03-11T00:00:00.000+09:00'
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => '2014-03-11T00:00:00.000+09:00'
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => '2014-03-11T00:00:00.000+09:00'
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end

    it 'cancel three with cancel_fee' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 189_750,
        'tax' => 17_250,
        'price_before_tax' => 172_500,
        'total_price' => 182_500,
        'total_discount' => -10_000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -6000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[0].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[1].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[2].status,
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today('2014-03-24')
      stub_now('2014-03-24 00:00:00')
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 106_808
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 106_808,
        'tax' => 9709,
        'price_before_tax' => 97_099,
        'total_price' => 97_099,
        'total_discount' => -10_000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -6000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 28_933,
                     'cancel_rate' => 80,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 18_083,
                     'cancel_rate' => 50,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 50_083,
                     'cancel_rate' => 50,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end

    it 'cancel three with cancel_fee one by one' do
      ps = create(:ps_credit_paid_points_used, :with_triple_student_status)
      ps.create_invoice! ps.created_at
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 189_750,
        'tax' => 17_250,
        'price_before_tax' => 172_500,
        'total_price' => 182_500,
        'total_discount' => -10_000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -6000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[0].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[1].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[2].status,
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today('2014-03-24')
      stub_now('2014-03-24 00:00:00')
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 181_500
      ).and_return(nil)
      ps.cancel_student_status(ps.student_statuses[0].id)
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 181_500,
        'tax' => 16_500,
        'price_before_tax' => 165_000,
        'total_price' => 173_000,
        'total_discount' => -8000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => -4000,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 30_000,
                     'cancel_rate' => 80,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[1].status,
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[2].status,
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today('2014-03-24')
      stub_now('2014-03-24 00:00:00')
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 163_075
      ).and_return(nil)
      ps.cancel_student_status(ps.student_statuses[1].id)
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 163_075,
        'tax' => 14_825,
        'price_before_tax' => 148_250,
        'total_price' => 152_250,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 30_000,
                     'cancel_rate' => 80,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 18_750,
                     'cancel_rate' => 50,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => ps.student_statuses[2].status,
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 0,
                     'cancel_rate' => 0,
                     'cancelled_at' => nil
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)

      # plan_keio:80% plan_todai:50% のキャンセル料
      stub_today('2014-03-24')
      stub_now('2014-03-24 00:00:00')
      expect(GMOPayment).to receive(:change_amount).with(
        kind_of(PaymentTransaction), 108_350
      ).and_return(nil)
      ps.cancel
      ps.invoices(true) # キャッシュクリア
      expected = {
        'price' => 108_350,
        'tax' => 9850,
        'price_before_tax' => 98_500,
        'total_price' => 98_500,
        'total_discount' => -4000,
        'payment_discount' => 0,
        'coupon_discount' => 0,
        'introduction_coupon_discount' => 0,
        'points_used' => -4000,
        'sibling_discount' => 0,
        'ss_prices' =>
              { ps.student_statuses[0].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[0].student.name,
                     'cancel_fee' => 30_000,
                     'cancel_rate' => 80,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[1].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 39_500,
                     'price' => 34_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[1].student.name,
                     'cancel_fee' => 18_750,
                     'cancel_rate' => 50,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   },
                ps.student_statuses[2].id.to_s =>
                   {
                     'preentry_discount' => 0,
                     'status' => 'cancelled',
                     'total' => 103_500,
                     'price' => 98_500,
                     'pc_rental_fee' => 5000,
                     'rental_prices' => { 'total_price' => 0, 'rentals' => [] },
                     'early_discount' => 0,
                     'travel_cost' => 0,
                     'student_name' => ps.student_statuses[2].student.name,
                     'cancel_fee' => 49_750,
                     'cancel_rate' => 50,
                     'cancelled_at' => '2014-03-24T00:00:00.000+09:00'
                   } }
      }
      expect(ps.price_info.deep_stringify_keys).to eq(expected)
    end
  end
end
