module Shared::PriceCalculation
  extend ActiveSupport::Concern
  include Shared::Params
  include CouponsHelper
  include CalculationHelper

  # 1 absence_with_notice per school is 2500yen
  ABSENCE_WITH_NOTICE_FEE = 2_500

  # 1 class per online is 3000yen
  ONLINE_FEE = 3_000

  # We are charging 6 sessions' (2 months) worth of payments first.
  FIRST_PAYMENT_COUNT = 6

  # Online has 30 sessions.
  ONLINE_COUNT = 30

  def self.sum_coupon_discounts(coupons, camp_id)
    total = 0
    apply_codes = []
    coupons.each do |c|
      if c.nil?
        next
      end
      if apply_codes.include? c.code
        next
      end

      total += get_discount_for_coupon(c, camp_id)
      apply_codes.push c.code
    end
    total
  end

  def self.get_discount_for_coupon(coupon, camp_id)
    Rails.logger.info "Checking coupon: #{coupon.code}"

    db_coupon = Coupon.for_camp(camp_id).find_by(code: coupon.code)

    if db_coupon && db_coupon.discount
      discount = db_coupon.discount
    else
      discount = 0
    end

    Rails.logger.info "Discount: #{discount}"
    discount
  end

  def clean_points_used(points_used)
    points_used ? points_used.to_s.gsub(/[^0-9]/, '') : 0
  end

  private

  ##
  # Calculate price for parent_status
  #
  # @param parent_status [ParentStatus] ParentStatus instance to calculate price for.
  # @param orig_ps [ParentStatus] Previous ParentStatus
  #
  # fixed_cancel_fee
  # キャンセル料を強制的にセットしたい場合に指定する
  # フォーマットは以下
  # {
  #   student_status_id => {
  #     cancel_fee: xxx,
  #     cancel_rate: yyy,
  #     cancelled_at: zzz,
  #   }
  # }
  def calculate_price(parent_status, fixed_cancel_fee = nil)
    apply_date = in_tokyo_date(parent_status.new_record? ? DateTime.now : ParentStatus.find(parent_status.id).created_at)
    # 兄弟割
    sibling_discount = -parent_status.sibling_discount * SIBLING_DISCOUNT
    # 支払い割
    payment_discount = parent_status.payment ? -parent_status.payment.discount : 0
    # クーポン割
    coupon_discount = parent_status.coupon_errors.empty? ? -Shared::PriceCalculation::sum_coupon_discounts(parent_status.coupons, parent_status.camp_id) : 0
    # 招待クーポン割
    introduction_coupon_discount = parent_status.introduction_coupon_errors.empty? && parent_status.introduction_coupon_used_histories.present? ? -parent_status.introduction_coupon_used_histories[0].introduction_coupon.discount : 0
    # ポイント
    points_used = -parent_status.points_used
    # 割引のトータル額
    total_discount = sibling_discount + payment_discount + coupon_discount + introduction_coupon_discount + points_used
    # 兄弟ごとの明細
    ss_prices = {}

    parent_status.student_statuses.each_with_index do |ss, index|
      ss_price = calculate_student_status_price(ss, apply_date)

      # キャンセル料の計算
      # https://github.com/lifeistech/members/issues/3605#issuecomment-399001600
      cancel ||= -> {
        if fixed_cancel_fee && fixed_cancel_fee[ss.id]
          return fixed_cancel_fee[ss.id]
        end

        # 前回の明細
        last_invoice = parent_status.invoices.last
        cancel_rate = CampCancelRate.cancel_rate(ss.plan, ss.cancelled_at.to_date)

        # 支払い済みの申込のみキャンセル料が発生する
        if parent_status.invoices.to_a.all? { |invoice| invoice.verified_at.blank? } || !ss.cancelled? || !last_invoice || cancel_rate == BigDecimal("0")
          return {
            cancel_fee: 0,
            cancel_rate: 0,
            cancelled_at: ss.cancelled_at,
          }
        end

        # 前回のキャンセル料を引き継ぎ
        if last_invoice.details_hash[:ss_prices][ss.id.to_s][:status] == "cancelled"
          return {
            cancel_fee: last_invoice.details_hash[:ss_prices][ss.id.to_s][:cancel_fee],
            cancel_rate: last_invoice.details_hash[:ss_prices][ss.id.to_s][:cancel_rate],
            cancelled_at: last_invoice.details_hash[:ss_prices][ss.id.to_s][:cancelled_at],
          }
        end

        # 全キャンセル
        if parent_status.cancelled?
          # 兄弟一括
          # ①AさんBさんを同時キャンセル
          is_multi_cancel = parent_status.cancelled? && last_invoice.details_hash[:ss_prices].values.count { |ss_p| ss_p[:status] != "cancelled" } > 1
          if is_multi_cancel
            return {
              cancel_fee: ((ss_price[:total] + total_discount / parent_status.student_statuses.count) * cancel_rate / 100).round,
              cancel_rate: cancel_rate.round,
              cancelled_at: ss.cancelled_at,
            }
          # 単品もしくは最後の一人
          # ③Bさんキャンセル完了後、Aさんをキャンセル(単体でクーポン&ポイント使った人も同じこと)
          else
            return {
              cancel_fee: ((ss_price[:total] + total_discount) * cancel_rate / 100).round,
              cancel_rate: cancel_rate.round,
              cancelled_at: ss.cancelled_at,
            }
          end
        # 個別キャンセル
        # ②Bさんのみをキャンセル
        else
          return {
            cancel_fee: ((ss_price[:total] - SIBLING_DISCOUNT) * cancel_rate / 100).round,
            cancel_rate: cancel_rate.round,
            cancelled_at: ss.cancelled_at,
          }
        end
      }.call

      ss_price[:cancel_fee] = cancel[:cancel_fee]
      ss_price[:cancel_rate] = cancel[:cancel_rate]
      ss_price[:cancelled_at] = cancel[:cancelled_at]

      if ss.id.present?
        ss_prices[ss.id.to_s] = ss_price
      else
        ss_prices["new_#{index}"] = ss_price
      end
    end

    # 兄弟のトータル額
    total_price = ss_prices.values.inject(0) do |sum, ss_price|
      if ss_price[:status] == "cancelled"
        next sum + ss_price[:cancel_fee]
      else
        next sum + ss_price[:total]
      end
    end

    # 割引を差し引いた料金
    if parent_status.cancelled?
      price_before_tax = total_price
    else
      price_before_tax = total_price + total_discount
    end
    price_before_tax = 0 if price_before_tax < 0

    # 消費税
    tax = CalculationHelper::calculate_tax(price_before_tax)

    # 料金調整分? 過去使われていたっぽいが現状は使っていなそう
    price_before_adjustment = price_before_tax + tax
    price = adjusted_price(price_before_adjustment, parent_status)

    ret = {
      price: price,
      tax: tax,
      price_before_tax: price_before_tax,
      total_price: total_price,
      total_discount: total_discount,
      payment_discount: payment_discount,
      coupon_discount: coupon_discount,
      introduction_coupon_discount: introduction_coupon_discount,
      points_used: points_used,
      sibling_discount: sibling_discount,
      ss_prices: ss_prices,
    }
    Rails.logger.info ret
    return ret
  end

  def adjusted_price(price_before_adjustment, parent_status)
    adjustment_payment = parent_status.new_record? ? 0 : parent_status.adjustment_payment

    if price_before_adjustment > adjustment_payment
      price = price_before_adjustment - adjustment_payment
    else
      price = 0
    end

    if adjustment_payment && adjustment_payment != 0
      Rails.logger.info "Manual adjustment: #{adjustment_payment}\n" +
                        'Appyling manual adjustment.'
    end
    return price
  end

  def calculate_student_status_price(ss, apply_date)
    if ss.plan_stayplan
      price = ss.plan_stayplan.price
      early_discount = -PlanStayplanDiscount.discount_for_date(ss.plan_stayplan.id, apply_date)
      travel_cost = ss.plan_stayplan.travel_cost || 0
    else
      price = 0
      early_discount = 0
      travel_cost = 0
    end

    if ss.pc_rental
      # NOTE: 変更前のレンタル代金算出ロジック、過去の情報参照のため残す
      pc_rental_fee = ss.plan.get_pc_rental_fee
      rental_prices = {
        total_price: 0,
        rentals: []
      }
    else
      pc_rental_fee = 0
      rental_prices = ss.rental_prices(ss.plan.try(:days_for_rental))
    end

    total = 0
    total += price
    total += pc_rental_fee
    total += rental_prices[:total_price] if rental_prices.has_key? :total_price
    total += early_discount
    total += travel_cost

    return {
      status: ss.status,
      total: total,
      price: price,
      pc_rental_fee: pc_rental_fee,
      rental_prices: rental_prices,
      early_discount: early_discount,
      travel_cost: travel_cost,
      student_name: ss.student.try(:name)
    }
  end

  def in_tokyo_date(datetime)
    datetime.in_time_zone('Tokyo').to_date
  end

  def school_entry_fee
    Integer(MembersConfiguration['school_entry_fee'])
  end

  def school_entry_discount(day_location, apply_date)
    school_discount = SchoolDiscount.find_by_date(apply_date)
    school_discount.try(:discount) || 0
  end

  def calculate_school_monthly(sc_params)
    day_location = sc_params.day_location

    if day_location.school_season.credit_card_enable?
      monthly_original = day_location.school_season.stripe_plan.amount
    else
      monthly_original = get_class_count(day_location.school_season) * sc_params.day_fee
    end

    # NOTE 今後月謝の割引が復活する可能性があり、JSON のレスポンスにも載せているので
    #   ゼロを代入しておこうと思います。
    #   There is a slight possibility that a monthly discount will be introduced
    #   again and the figure is currently used in the JSON response so we will
    #   keep the variable and assign a zero just in case.
    monthly_discount = 0
    monthly_total = monthly_original - monthly_discount
    monthly_tax = CalculationHelper::calculate_tax(monthly_total)
    monthly_price = monthly_total + monthly_tax

    return {
      monthly_price: monthly_price,
      monthly_tax: monthly_tax,
      monthly_total: monthly_total,
      monthly_original: monthly_original,
      monthly_discount: monthly_discount,
    }
  end

  def calculate_school_entry_fee(sc_params)
    day_location = sc_params.day_location
    if sc_params.student \
          && sc_params.student.should_discount_school_entry?(day_location)
      return {
        entry_price: 0,
        entry_tax: 0,
        entry_total: 0,
        entry_original: 0,
        early_discount: 0,
        coupon_discount: 0,
        points_used: 0,
        points_left: sc_params.parent.points,
      }
    end

    entry_original = entry_total = sc_params.entry_fee

    # 早期割引
    early_discount = -day_location.entry_discount(sc_params.apply_date, sc_params.student)
    entry_total += early_discount
    entry_total = entry_total < 0 ? 0 : entry_total

    # クーポン割引
    coupon_discount = 0
    coupon_used = sc_params.coupon_used
    unless coupon_used.blank?
      Rails.logger.info "Coupon used: #{coupon_used}"
      coupons = Coupon.for_school.where(code: coupon_used)

      if coupons.size > 0
        coupon = coupons.first
        Rails.logger.info "Applying coupon discount: #{coupon.discount}"
        coupon_discount = -coupon.discount
      else
        Rails.logger.warn "Coupon #{coupon_used} not found."
      end
    end
    entry_total += coupon_discount

    # ポイント割引
    points_used = sc_params.points_used ? Integer(sc_params.points_used) : 0
    if points_used > entry_total
      Rails.logger.info 'Points exceed entry fee. Correcting...'
      points_used = entry_total
    end
    entry_total -= points_used
    points_left = sc_params.parent ? sc_params.parent.points - points_used : 0

    # 消費税計算
    entry_tax = CalculationHelper::calculate_tax(entry_total)
    entry_price = entry_total + entry_tax

    return {
      entry_price: entry_price,
      entry_tax: entry_tax,
      entry_total: entry_total,
      entry_original: entry_original,
      early_discount: early_discount,
      coupon_discount: coupon_discount,
      points_used: points_used,
      points_left: points_left,
    }
  end

  def calculate_full_payment(sc_params, school_monthly, school_entry_fee)
    # クレカ支払いできない人のための応急処置で
    # 全額一括支払いの合計金額を計算
    remaining_payments_count = sc_params.day_location.school_season.remaining_payments_count || 0
    # 税込の月謝から金額を算出する（税抜き金額から算出するとずれることがある為）
    # full_monthly_total = school_monthly[:monthly_total] * remaining_payments_count
    # full_monthly_tax = CalculationHelper::calculate_tax(full_monthly_total)
    # full_monthly_price = full_monthly_total + full_monthly_tax
    full_monthly_price = school_monthly[:monthly_price] * remaining_payments_count
    full_monthly_total = CalculationHelper::exclude_tax(full_monthly_price)
    full_monthly_tax = full_monthly_price - full_monthly_total

    full_payment_total = school_entry_fee[:entry_total] + full_monthly_total
    full_payment_tax = CalculationHelper::calculate_tax(full_payment_total)
    full_payment_price = full_payment_total + full_payment_tax
    return {
      full_monthly_price: full_monthly_price,
      full_monthly_tax: full_monthly_tax,
      full_monthly_total: full_monthly_total,
      full_payment_price: full_payment_price,
      full_payment_tax: full_payment_tax,
      full_payment_total: full_payment_total,
    }
  end

  def calculate_school(sc_params)
    school_monthly = calculate_school_monthly(sc_params)
    Rails.logger.info "school_monthly: #{school_monthly}"

    school_entry_fee = calculate_school_entry_fee(sc_params)
    Rails.logger.info "school_entry_fee: #{school_entry_fee}"

    school_full_payment = calculate_full_payment(sc_params, school_monthly, school_entry_fee)
    Rails.logger.info "school_full_payment: #{school_full_payment}"

    result = SchoolCalculationResult.new
    result.assign_attributes school_monthly
    result.assign_attributes school_entry_fee
    result.assign_attributes school_full_payment
    Rails.logger.info "Result is #{result}"

    result
  end

  def calculate_school_monthly_fee(sc_params)
    school_attendances = SchoolAttendance.attendances_at_month(
      sc_params.school_application, sc_params.apply_date
    )

    attendance_times = school_attendances.attended.count
    absence_times = school_attendances.absent_with_notice.count
    Rails.logger.info "Attendance times: #{attendance_times}"
    Rails.logger.info "Absence times: #{absence_times}"

    fee = school_monthly_fee_without_tax(attendance_times, absence_times, sc_params.day_fee)
    Rails.logger.info "School Monthly fee without tax: #{fee}"

    tax = CalculationHelper::calculate_tax(fee)
    Rails.logger.info "Tax: #{tax}"

    fee + tax
  end

  def school_monthly_fee_without_tax(attendances_time, absences_time, day_fee)
    attendances_time * day_fee + absences_time * ABSENCE_WITH_NOTICE_FEE
  end

  def get_class_count(school_season)
    # 初回振込月謝用クラス数
    school_season.try(:first_tuition_number_of_times) || 0
  end

  def online_first_payment
    ONLINE_FEE * FIRST_PAYMENT_COUNT
  end

  def calculate_online_first_payment(payment_id, apply_date)
    # TODO: rename to first_payment.
    monthly_payment = online_first_payment
    monthly_payments_total = ONLINE_FEE * ONLINE_COUNT

    Rails.logger.info "Monthly payment: #{monthly_payment}\n" +
                      "Total monthly payments: #{monthly_payments_total}"

    if Payment.find(payment_id).bank_withdraw?
      price_without_tax = monthly_payment
      payment_method = 'bank_withdraw'
    else
      price_without_tax = monthly_payments_total
      payment_method = 'bank'
    end

    Rails.logger.info "Price without tax: #{price_without_tax}"

    tax = CalculationHelper::calculate_tax(price_without_tax)

    Rails.logger.info "Tax: #{tax}"

    price = price_without_tax + tax

    OnlineCalculationResult.new(
      monthly_payment, monthly_payments_total, tax,
      price, payment_method
    )
  end

  class SchoolCalculationParams
    constructor :apply_date, :day_location, :parent,
                :school_application, :coupon_used, :student, :points_used, :day_fee, :entry_fee,
                accessors: true, strict: false
  end

  OnlineCalculationResult = Struct.new(
    :monthly_payment, :monthly_payments_total, :tax, :price,
    :payment_method
  ) do
    def to_s
      "Price: #{price} Monthly Payment: #{monthly_payment}" +
        "Monthly Payments Total: #{monthly_payments_total}, " +
        "Tax: #{tax}"
    end
  end
end
