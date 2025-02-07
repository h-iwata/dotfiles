class ParentStatusesController < ApplicationController
  include Shared::Params
  include Shared::PriceCalculation
  include PriceDisplayHelper
  include RedisHelper

  layout :choose_layout

  NoAuthActions = [
    :update_payment, :report, :apply_start,
    :apply_camp_select, :apply_parent_info, :apply_student_info,
    :show_confirm, :apply_payment, :complete_bank, :complete_credit,
    :complete_pending_cancel,
  ].freeze

  before_action :set_parent_status, only: [:show, :edit,
                                           :destroy, :confirm, :payment_for_edit, :execute, :details, :cancel_start, :refund,
                                           :execute_cancel, :show_payment, :payment_execute, :edit_complete, :change_request_complete, :complete]
  before_action :set_parent_status_change_request, only: [:show_parent_status_change_request, :cancel_parent_status_change_request]
  before_action :block_cancelled, only: [:show, :edit, :confirm, :payment_for_edit, :cancel_start, :execute_cancel]
  before_action :authenticate_parent_or_admin!, except: NoAuthActions
  before_action :authenticate_current_parent_or_admin!,
                except: NoAuthActions + [:apply_start_logged_in, :mypage]
  before_action :authenticate_admin_user!, only: [:update_payment, :report]
  before_action :check_deadline!, only: [:cancel]
  before_action :check_change_request_deadline!, only: [:edit, :payment_for_edit]
  before_action :check_cancels_allowed!, only: [:cancel_start, :execute_cancel]
  before_action :set_apply_bg, only: [:mypage]
  before_action :hide_password, only: [:new, :edit]
  before_action :set_camp,
                only: [:apply_start, :apply_start_logged_in, :apply_camp_select]

  Steps = Struct.new(:current, :last)
  PreSelect = Struct.new(:plan_id, :course_id, :stayplan_id)

  # GET /
  def mypage
    @parent ||= current_parent

    unless @parent
      logger.warn 'Not logged in as parent. Redirecting to login page.'
      return redirect_to new_parent_session_path
    end

    logger.info "Displaying list for parent ID: #{@parent.id}"
    @parent_statuses = ParentStatus.includes(:camp, { student_statuses: [:plan, :camp, :stayplan, :student] })
                                   .where(parent: @parent)
                                   .where.not(status: ParentStatus::PENDING_CONFIRMATION)
                                   .where('(NOT(payment_id IN (?) AND status = ?)) OR payment_id IS NULL', Payment.credit_card_ids,
                                          ParentStatus::PENDING_PAYMENT)
                                   .order(id: "DESC")

    @introduction_coupon = @parent.current_introduction_coupon
    @show_school_continue_survay = @parent.school_applications.any? { |v| v.school_season&.next_season && v.school_season.passed_survey_startline? && v.school_season.is_current? && v.survey_answered? }
  end

  # GET /parent_statuses/1
  # GET /parent_statuses/1.json
  def show
    @camp = @parent_status.camp
  end

  # GET  /parent_statuses/1/edit
  # POST /parent_statuses/1/edit
  def edit
    @parent_status.parent.set_email_confirm
    @camp = @parent_status.camp

    if request.get?
      new_edit
    else
      back_to_edit
    end
  end

  def new_edit
    @is_parent_cancel = false
    @show_password = false

    render :edit
  end

  def confirm
    new_ps = ParentStatus.new(camp_ps_params_all)

    @old_price = calculate_price(@parent_status)[:price]

    @parent_status.copy_from_new_status new_ps

    unless @parent_status.valid?
      logger.error "Failed to validate new ParentStatus: " +
                   @parent_status.errors.full_messages.join(',')
      @error_model = @parent_status
      render_edit
      return
    end

    @new_price = calculate_price(@parent_status)[:price]
    @price_diff = @new_price - @old_price

    logger.info "Old price: #{@old_price}"
    logger.info "New price: #{@new_price}"

    @camp = @parent_status.camp

    render :confirm, locals: {
      parent_status: @parent_status,
      is_edit: true,
      payment_path: payment_parent_status_path(@parent_status),
      back_path: edit_parent_status_path(@parent_status),
      parent_id: nil,
      student_ids: [],
      steps: nil,
      show_legacy_step_boxes: true,
      plan_type_name: nil,
    }
  end

  def back_to_edit
    new_ps = ParentStatus.new(camp_ps_params_all)
    @parent_status.copy_from_new_status new_ps
    @parent_status.payment = new_ps.payment

    render_edit
  end

  # GET /parent_statuses/:id/payment
  def show_payment
    if @parent_status.status == ParentStatus::PENDING_PAYMENT && @parent_status.payment.credit_card?
      render_payment(@parent_status, execute_parent_status_path(@parent_status), true,
                     nil, [], true)
    else
      redirect_to parent_status_path(@parent_status)
    end
  end

  # POST /parent_statuses/:id/payment
  def payment_for_edit
    @status_before = @parent_status.status

    process_diffs

    unless is_plan_courses_active(@parent_status, @ss_diffs)
      return redirect_to edit_parent_status_path(id: @parent_status.id), \
                         flash: { alert: '申し訳ありません。コースが締め切られました。他のコースをご選択ください。' }
    end

    @camp = @parent_status.camp

    # If it was a bank payment and the user has already paid, display a refund
    # page.
    if @price_diff < 0 &&
       (@parent_status.need_bank_refund? ||
        (@parent_status.price == 0 && @old_payment.bank? && @parent_status.paid?))
      return render :refund_bank, locals: { refund_bank_account: refund_bank_account_or_initialize }
    end

    # 変更締切後は変更内容のみ保存し、承認はadmin画面から行う
    if save_edit_request_if_changes_not_allowed
      return
    end

    if @parent_status.paid? && @parent_status.is_bank && @price_diff > 0
      @parent_status.money_received = false
    end

    @parent_status.parent.skip_password_verification = true
    if @parent_status.price == 0
      @parent_status.money_received = true
    end

    case @parent_status.status
    when ParentStatus::PENDING_PAYMENT
      if @parent_status.payment.present? && @parent_status.payment.credit_card?
        # Redirect to input_credit_information
        redirect_to payment_parent_status_path(@parent_status)
      elsif @parent_status.payment.bank?
        redirect_to edit_complete_parent_status_path(@parent_status)
      end
    when ParentStatus::PAID
      if @parent_status.is_free_camp?
        redirect_to edit_complete_parent_status_path(@parent_status)
      elsif @parent_status.no_charge?
        if @old_payment.try(:credit_card?)
          @parent_status.cancel_credit_card_payment
        end
        redirect_to edit_complete_parent_status_path(@parent_status)
      elsif @parent_status.payment.credit_card?
        # Change the credit's payment price
        unless @price_diff == 0
          begin
            # クレカ情報の再入力があったケース
            if params.has_key? :credit_card
              logger.info 'Update with new credit card.'
              credit_card = CreditCard.build_from_params(params)
              unless credit_card.valid?
                @parent_status.errors[:base].concat(credit_card.errors.full_messages).uniq!
                plan_type_name = @parent_status.plan_type_name
                render 'edit_payment', locals: { parent_status: @parent_status,
                                                 error_model: @parent_status, plan_type_name: plan_type_name }
                return
              end
              unless @parent_status.change_credit_card_amount_with_new_card credit_card
                @parent_status.errors[:base].uniq!
                plan_type_name = @parent_status.plan_type_name
                render 'edit_payment', locals: { parent_status: @parent_status,
                                                 error_model: @parent_status, plan_type_name: plan_type_name }
                return
              end
            else
              @parent_status.change_credit_card_amount
              @parent_status.save!
            end
          rescue PaymentError => e
            @parent_status.errors[:base].concat(e.error_messages).uniq!

            plan_type_name = @parent_status.plan_type_name
            render 'edit_payment', locals: { parent_status: @parent_status,
                                             error_model: @parent_status, plan_type_name: plan_type_name }
            return
          end
        end
        redirect_to edit_complete_parent_status_path(@parent_status)
      elsif @parent_status.payment.bank?
        # Redirect to complete
        redirect_to edit_complete_parent_status_path(@parent_status)
      end
    when ParentStatus::PENDING_OTHER_CANCEL
      logger.info 'Still in pending cancel.'
      redirect_to edit_complete_parent_status_path(@parent_status)
    when ParentStatus::PENDING_DRAW
      logger.info 'Still in pending draw. Just displaying complete.'
      redirect_to edit_complete_parent_status_path(@parent_status)
    end

    if !@parent_status.payment.nil? && @parent_status.payment.credit_card?
      verified_at = Time.zone.now
    else
      if @parent_status.paid? && @price_diff == 0
        verified_at = Time.zone.now
      else
        verified_at = nil
      end
    end
    @parent_status.save!
    @parent_status.create_invoice!(verified_at)
    send_change_email(@ps_diff, @ss_diffs, @old_payment, @status_before, @ss_rental_diffs)
  end

  # PATCH /parent_statuses/:id/execute
  def payment_execute
    credit_card = CreditCard.build_from_params(params)
    if @parent_status.execute_payment(credit_card)
      redirect_to edit_complete_parent_status_path(@parent_status)
    else
      logger.warn "Failed with #{@parent_status.errors.full_messages}"
      render_payment(@parent_status, execute_parent_status_path(@parent_status), true,
                     nil, [], true)
    end
  end

  # GET /parent_statuses/:id/edit_complete
  def edit_complete
    render :change_complete
    check_plan_close(@parent_status)
    check_plan_course_close(@parent_status)
  end

  # GET /parent_statuses/:id/change_request_complete
  def change_request_complete
    render :change_request_complete
  end

  # PATCH /parent_statuses/1/refund
  def refund
    @status_before = @parent_status.status
    process_diffs

    refund_bank_account = refund_bank_account_or_initialize
    unless refund_bank_account.update_attributes(parent_bank_account_params)
      return render :refund_bank, locals: { refund_bank_account: refund_bank_account }
    end

    # 変更締切後は変更内容のみ保存し、承認はadmin画面から行う
    if save_edit_request_if_changes_not_allowed
      return
    end

    if @parent_status.save
      @parent_status.create_invoice!(nil)
      send_change_email(@ps_diff, @ss_diffs, @old_payment, @status_before)
      send_refund_email refund_bank_account
      redirect_to edit_complete_parent_status_path(@parent_status)
    else
      return render :refund_bank, locals: { refund_bank_account: refund_bank_account_or_initialize }
    end
  end

  # DELETE /parent_statuses/1
  # DELETE /parent_statuses/1.json
  def destroy
    @parent_status.destroy
    respond_to do |format|
      format.html { redirect_to parent_statuses_url }
      format.json { head :no_content }
    end
  end

  # GET /parent_status/:id/cancel_start
  def cancel_start
    @parent_status.cancel(false)
    price_info_to = @parent_status.price_info

    if @parent_status.need_bank_refund?
      return render :cancel_start, locals: { price_info_to: price_info_to, refund_bank_account: refund_bank_account_or_initialize }
    end

    render :cancel_start, locals: { price_info_to: price_info_to }
  end

  # PATCH /parent_status/:id/cancel_start
  def execute_cancel
    if @parent_status.need_bank_refund?
      refund_bank_account = refund_bank_account_or_initialize
      unless refund_bank_account.update_attributes(parent_bank_account_params)
        @parent_status.cancel(false)
        price_info_to = @parent_status.price_info
        return render :cancel_start, locals: { price_info_to: price_info_to, refund_bank_account: refund_bank_account }
      end
    end

    cancel_reason_id = cancel_reason_param[:cancel_reason]

    cancelled_student_statuses = []
    begin
      ActiveRecord::Base.transaction do
        begin
          cancelled_student_statuses = @parent_status.cancel(true, cancel_reason_id)
        rescue
          logger.error "Failed to save a cancelled ParentStatus #{@parent_status.errors.full_messages}"
          raise
        end
      end
    rescue PaymentError => e
      logger.warn e.cause
      logger.warn e.error_codes
      logger.warn e.error_messages
      logger.warn e.message
      logger.warn e.backtrace.join("\n")
      return render :cancel_payment_error
    end

    other_apps = @parent_status.other_applications

    @need_recalc = other_apps.length > 0

    if cancel_reason_id && !cancel_reason_id.blank?
      @cancel_reason_id = cancel_reason_id.to_i
    end

    @other_reason = other_reason_param[:other_reason]

    refund_bank_account = @parent_status.is_bank ? refund_bank_account : nil

    send_cancel_email(refund_bank_account, cancelled_student_statuses)

    respond_to do |format|
      format.html { render :cancel_complete }
      format.json { head :no_content }
    end
  end

  def contact
    render :template_contact
  end

  # POST /update_payment
  def update_payment
    ps_list = ParentStatus.where(parent_status_id_param)

    payment_date = Date.parse("#{payment_date_param['year']}-#{payment_date_param['month']}-#{payment_date_param['day']}")

    ps_list.each do |ps|
      ps.money_received = true
      ps.payment_date = payment_date
      ps.save

      last_invoice = ps.invoices.last
      if last_invoice
        last_invoice.verified_at = Time.zone.now
        last_invoice.save!
      end

      PaymentBank.create!({
                            parent_status: ps,
                            price: ps.price
                          })

      send_payment_confirmed_email(ps)
    end

    redirect_to admin_parent_statuses_path, flash: { alert: '支払い確認メールを送信しました' }
  end

  # POST /report
  def report
    send_to_worker(ReportWorker::ParentStatusCSV, report_params[:to])
    redirect_to admin_parent_statuses_path, flash: { alert: 'レポートを作り始めました。' }
  end

  # GET /camps/:camp_id/apply_start
  def apply_start
    plan_type_name = get_plan_type_name

    pre_select = build_pre_select

    options = {}
    options[:plan_type_name] = plan_type_name if plan_type_name
    options[:pre_select] = pre_select if pre_select

    render_apply_start(options)
  end

  # GET /camps/:camp_id/apply_start_logged_in
  def apply_start_logged_in
    redirect_to apply_start_camp_path(@camp, request.query_parameters)
  end

  # GET  /camps/:camp_id/apply_camp_select
  # POST /camps/:camp_id/apply_camp_select
  def apply_camp_select
    plan_type_name = get_plan_type_name
    is_back = came_from_back_button
    any_code_or_points = params[:any_code_or_points]
    any_code = params[:any_code]

    if @camp.passed_apply_deadline?
      render_apply_start
    elsif !is_back && params[:accept_tos] != '1'
      error_message = '申込約款にご同意の上、お申込みください。'
      pre_select = build_pre_select
      opts = { plan_type_name: plan_type_name, error_message: error_message }
      opts[:pre_select] = pre_select if pre_select
      render_apply_start(opts)
    else
      parent_status = build_parent_status(is_back)

      parent_status.camp = @camp

      if !is_back && current_parent
        parent_status.parent = current_parent
      end

      render_apply_camp_select(parent_status, plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:camp_id/apply_parent_info
  def apply_parent_info
    plan_type_name = get_plan_type_name
    parent_id = params[:parent_id]
    any_code_or_points = params[:any_code_or_points]
    any_code = params[:any_code]

    if any_code_or_points == 'any_code' && any_code.present? &&
       if ParentStatus.is_introduction_coupon_code(any_code)
         any_code = any_code.upcase
       end
    end

    parent_status = ParentStatus.build_for_apply(
      camp_ps_params_with_parent_and_student_id
    )
    parent_status.reflect_any_code(any_code, parent_id) if any_code_or_points == 'any_code' && any_code.present?

    if params.key?(:parent_id) || !parent_status.parent
      parent_status.parent = current_parent ? current_parent.clone : Parent.new
    end
    if parent_status.validate_camp_info
      parent_status.parent.set_email_confirm

      render_apply_parent_info(parent_status, parent_id, plan_type_name, any_code_or_points, any_code)
    else
      logger.info "Invalid camp info with #{parent_status.errors.full_messages}"
      render_apply_camp_select(parent_status, plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:camp_id/apply_student_info
  def apply_student_info
    is_back = came_from_back_button
    plan_type_name = get_plan_type_name
    parent_id = params[:parent_id]
    any_code_or_points = params[:any_code_or_points]
    any_code = params[:any_code]

    parent_status = ParentStatus.build_for_apply(
      camp_ps_params_with_parent_and_student_id
    )
    parent_status.reflect_any_code(any_code, parent_id) if any_code_or_points == 'any_code' && any_code.present?

    unless replace_parent_if_necessary(parent_status, parent_id)
      return
    end

    parent_status.replace_with_db_coupons

    if is_back || parent_status.validate_parent_info
      student_ids = nil

      parent_status.student_statuses.map do |ss|
        student_id = ss.student.try(:id)

        if student_id.present?
          student_ids ||= []
          student_ids.push(student_id)
        else
          ss.build_student
        end
      end

      render_apply_student_info(parent_status, parent_id, student_ids, plan_type_name, any_code_or_points, any_code)
    else
      logger.info "Invalid parent info with #{parent_status.errors.full_messages}"
      parent = parent_status.parent
      if parent.email == parent.email_confirm
        parent_status.parent.set_email_confirm
      end
      render_apply_parent_info(parent_status, parent_id, plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:camp_id/show_confirm
  def show_confirm
    parent_id = params[:parent_id]
    student_ids = params[:student_ids]
    any_code_or_points = params[:any_code_or_points]
    any_code = params[:any_code]

    plan_type_name = get_plan_type_name

    parent_status = build_complete_ps(parent_id, student_ids, any_code_or_points, any_code)
    return unless parent_status

    replace_birthdays(parent_status)
    parent_status.update_pending_cancel

    if parent_status.valid?
      render_apply_confirm(parent_status, parent_id, student_ids,
                           plan_type_name, any_code_or_points, any_code)
    else
      logger.info "Invalid parent_status with #{parent_status.errors.full_messages}"
      render_apply_student_info(parent_status, parent_id, student_ids, plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:camp_id/apply_payment
  def apply_payment
    parent_id = params[:parent_id]
    student_ids = params[:student_ids]
    any_code_or_points = params[:any_code_or_points]
    any_code = params[:any_code]
    plan_type_name = get_plan_type_name

    parent_status = build_complete_ps(parent_id, student_ids, any_code_or_points, any_code)
    parent_status.update_pending_cancel

    if parent_status.valid?
      if parent_status.is_credit_card && !parent_status.is_pending_cancel?
        render_payment(parent_status,
                       complete_credit_camp_path(parent_status.camp), false, parent_id, student_ids,
                       false, plan_type_name, any_code_or_points, any_code)
        return
      end
    else
      logger.error "ParentStatus was invalid with #{parent_status.errors.full_messages}"
      render_apply_confirm(parent_status, parent_id, student_ids,
                           plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:id/complete_bank
  # POST /camps/:id/complete_pending_cancel
  def complete_bank
    parent_id = params[:parent_id]
    student_ids = params[:student_ids]
    any_code = params[:any_code]
    any_code_or_points = params[:any_code_or_points]
    plan_type_name = get_plan_type_name

    parent_status = build_complete_ps(parent_id, student_ids, any_code_or_points, any_code)
    parent_status.update_pending_cancel

    unless is_plan_courses_active(parent_status)
      return redirect_to apply_camp_select_camp_path(id: parent_status.camp_id, accept_tos: '1'), \
                         flash: { alert: '申し訳ありません。コースが締め切られました。他のコースをご選択ください。' }
    end

    if parent_status.valid?
      begin
        ActiveRecord::Base.transaction do
          parent_status.save!
          parent_status.create_invoice!

          if parent_status.points_used?
            parent = parent_status.parent
            parent.use_points(parent_status.points_used, resource: parent_status)
          end
        end

        parent_status.send_apply_email(!current_parent)

        render_complete(parent_status)

        check_plan_close(parent_status)
        check_plan_course_close(parent_status)

        return
      rescue => e
        logger.error "Failed to complete application. Error: #{e}"
        render_apply_confirm(parent_status, parent_id, student_ids, plan_type_name, any_code_or_points, any_code)
      end
    else
      logger.error "ParentStatus was invalid with #{parent_status.errors.full_messages}"
      render_apply_confirm(parent_status, parent_id, student_ids, plan_type_name, any_code_or_points, any_code)
    end
  end

  # POST /camps/:camp_id/complete_credit
  def complete_credit
    parent_id = params[:parent_id]
    student_ids = params[:student_ids]
    any_code = params[:any_code]
    any_code_or_points = params[:any_code_or_points]
    plan_type_name = get_plan_type_name

    parent_status = build_complete_ps(parent_id, student_ids, any_code_or_points, any_code)

    unless is_plan_courses_active(parent_status)
      return redirect_to apply_camp_select_camp_path(id: parent_status.camp_id, accept_tos: '1'), \
                         flash: { alert: '申し訳ありません。コースが締め切られました。他のコースをご選択ください。' }
    end

    credit_card = CreditCard.build_from_params(params)

    if credit_card.valid?
      begin
        ActiveRecord::Base.transaction do
          parent_status.save!
          parent_status.create_invoice! Time.zone.now

          if parent_status.execute_payment(credit_card)
            if parent_status.points_used?
              parent = parent_status.parent
              parent.use_points(parent_status.points_used, resource: parent_status)
            end

            render_complete(parent_status)
            check_plan_close(parent_status)
            check_plan_course_close(parent_status)
          else
            raise 'Failed payment execution.'
          end
        end
        parent_status.send_apply_email(!current_parent)
        return
      rescue Exception => e
        logger.error "Failed to execute payment. Error: #{e}"
        logger.error e.backtrace.join("\n")
      end
    else
      credit_card.errors.full_messages.each do |fm|
        parent_status.errors.add(:base, fm)
      end
    end

    parent_status.student_statuses.map { |ss| ss.id = nil }
    render_payment(parent_status, complete_credit_camp_path(parent_status.camp),
                   false, parent_id, student_ids, false, plan_type_name, any_code_or_points, any_code)
  end

  # GET /parent_statuses/:id/complete
  def complete
    render_complete(@parent_status)
    check_plan_close(parent_status)
    check_plan_course_close(parent_status)
  end

  def show_parent_status_change_request
    @parent_status_org = @parent_status_change_request.parent_status
    @parent_status_new = @parent_status_change_request.get_applied_parent_status
    @camp = @parent_status_new.camp

    @old_price = @parent_status_org.price
    @new_price = @parent_status_new.price
    @price_diff = @new_price - @old_price
  end

  def cancel_parent_status_change_request
    @parent_status_change_request.cancel
  end

  private

  def set_parent_status
    if params[:id]
      @parent_status = ParentStatus.find(params[:id])
      @parent = @parent_status.parent
    end
  end

  def set_parent_status_change_request
    if params[:parent_status_change_request_id]
      @parent_status_change_request = ParentStatusChangeRequest.find(params[:parent_status_change_request_id])
      @parent = @parent_status_change_request.parent_status.parent
    end
  end

  def block_cancelled
    if @parent_status && (@parent_status.cancelled? || @parent_status.is_invalid?)
      return not_found
    end
  end

  def set_camp
    @camp = Camp.find(params[:id])
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def parent_status_params
    params.require(:parent_status).permit(parent_status_attrs)
  end

  def report_params
    params.permit(:to)
  end

  def is_parent_cancel?
    params[:type] == "parent_cancel"
  end

  def choose_layout
    needs_new_camp_layout = %w(
      apply_start apply_start_logged_in apply_camp_select apply_parent_info
      apply_student_info show_confirm apply_payment complete_bank complete_credit
      complete_pending_cancel
    )

    if needs_new_camp_layout.include? action_name
      'new_camp_apply'
    else
      'application'
    end
  end

  def render_edit
    @camp = @parent_status.camp

    @parent_status.parent.set_email_confirm

    @stayplans = @parent_status.available_stayplans
    @courses = @parent_status.available_courses

    @show_password = false

    render :edit
  end

  def render_apply_start(options = {})
    plan_type_name = options[:plan_type_name]
    error_message = options[:error_message]
    pre_select = options[:pre_select]
    render :apply_start, locals: { camp: @camp, plan_type_name: plan_type_name,
                                   error_message: error_message, pre_select: pre_select }
  end

  def render_apply_camp_select(parent_status, plan_type_name, any_code_or_points, any_code)
    camp = parent_status.camp

    render :apply_camp_select,
           locals: { parent_status: parent_status,
                     camp: camp,
                     plan_type_name: plan_type_name,
                     plan_stayplans: parent_status.available_plan_stayplans,
                     pc_types: parent_status.available_pc_types,
                     payments: parent_status.available_payments,
                     logged_in_parent: current_parent,
                     steps: Steps.new(1, 6),
                     any_code_or_points: any_code_or_points,
                     any_code: any_code }
  end

  def render_apply_parent_info(parent_status, parent_id, plan_type_name, any_code_or_points = nil, any_code = nil)
    render :apply_parent_info,
           locals: { parent_status: parent_status,
                     show_password: !current_parent,
                     parent_id: parent_id,
                     steps: Steps.new(2, 6),
                     plan_type_name: plan_type_name,
                     any_code_or_points: any_code_or_points,
                     any_code: any_code, }
  end

  def render_apply_student_info(parent_status, parent_id, student_ids = nil, plan_type_name = nil, any_code_or_points = nil, any_code = nil)
    students = current_parent ? current_parent.students : Student.none
    ss_count = parent_status.student_statuses.size
    student_ids ||= Array.new(ss_count, '')

    render :apply_student_info, locals: {
      parent_status: parent_status, grade_list: parent_status.camp.is_spring? ? Student.grades_list_spring : Student.grades_list,
      experiences: Experience.active, students: students,
      learned_reasons: LearnedReason.active.ordered,
      parent_id: parent_id, student_ids: student_ids,
      steps: Steps.new(3, 6), plan_type_name: plan_type_name,
      any_code_or_points: any_code_or_points,
      any_code: any_code,
    }
  end

  def render_complete(parent_status)
    render :complete,
           locals: { parent_status: parent_status, steps: Steps.new(6, 6),
                     show_legacy_step_boxes: false }
  end

  def came_from_back_button
    params[:back] == '1'
  end

  def build_pre_select
    plan_id = params[:plan_id]
    course_id = params[:course_id]
    stayplan_id = params[:stayplan_id]

    return nil if !plan_id && !course_id && !stayplan_id

    PreSelect.new(plan_id, course_id, stayplan_id)
  end

  # Builds the {ParentStatus} from the parameters.
  #
  # @param is_back [Boolean] Whether the user reached here by pressing the
  #   'back' button.
  # @return [ParentStatus] The {ParentStatus} built.
  def build_parent_status(is_back)
    if is_back
      tmp_ps = ParentStatus.build_for_apply(
        camp_ps_params_with_parent_and_student_id
      )

      tmp_ps.student_statuses.build if tmp_ps.student_statuses.empty?

      tmp_ps
    else
      tmp_ps = ParentStatus.new
      tmp_ps.student_statuses.build
      first_ss = tmp_ps.student_statuses.first
      first_ss.set_pre_selected(build_pre_select)
      tmp_ps
    end
  end

  def render_apply_confirm(parent_status, parent_id, student_ids, plan_type_name, any_code_or_points = nil, any_code = nil)
    camp = parent_status.camp
    next_path = if parent_status.is_credit_card
                  apply_payment_camp_path(camp)
                elsif parent_status.is_pending_cancel?
                  complete_pending_cancel_camp_path(camp)
                else
                  complete_bank_camp_path(camp)
      end

    render :confirm, locals: {
      parent_status: parent_status,
      is_edit: false,
      payment_path: next_path,
      back_path: apply_student_info_camp_path(parent_status.camp),
      parent_id: parent_id,
      student_ids: student_ids,
      steps: Steps.new(4, 6),
      show_legacy_step_boxes: false,
      plan_type_name: plan_type_name,
      any_code_or_points: any_code_or_points,
      any_code: any_code,
    }
  end

  def render_payment(parent_status, execute_path, include_existing_ids,
                     parent_id = nil, student_ids = [], show_legacy_step_boxes = false,
                     plan_type_name = nil, any_code_or_points = nil, any_code = nil)

    render :payment, locals: {
      parent_status: parent_status, credit_card: CreditCard.new,
      execute_path: execute_path, include_existing_ids: include_existing_ids,
      parent_id: parent_id, student_ids: student_ids, steps: Steps.new(5, 6),
      show_legacy_step_boxes: show_legacy_step_boxes,
      plan_type_name: plan_type_name,
      any_code_or_points: any_code_or_points,
      any_code: any_code,
    }
  end

  # Add background with picture.
  def set_apply_bg
    @body_class = "apply-bg"
  end

  ##
  # hide_password hides the password entry field.
  def hide_password
    @show_password = false
  end

  # Update points left for the parent by comparing the points used in
  # @parent_status (based on params) versus the value stored in the database.
  def update_points_left
    original_ps = ParentStatus.find(@parent_status.id)

    # Change points
    @parent.points -= (@parent_status.points_used - original_ps.points_used)
  end

  def send_change_email(ps_diff, ss_diffs, old_payment, status_before, ss_rental_diffs = [])
    UserMailerWorker.perform_async_or_default(
      UserMailerWorker::CHANGE, @parent_status.id,
      diff: { parent_status: ps_diff, student_statuses: ss_diffs,
              student_status_camp_rentals: ss_rental_diffs,
              old_payment_bank: old_payment.present? && old_payment.bank?,
              old_payment_credit_card: old_payment.present? && old_payment.credit_card?,
              status_before: status_before }
    )
  end

  def send_change_request_email(parent_status_change_request)
    UserMailerWorker.perform_async_or_default(
      UserMailerWorker::CHANGE_REQUEST, @parent_status.id,
      parent_status_change_request_id: parent_status_change_request.id
    )
  end

  def send_cancel_email(refund_bank_account = nil, cancelled_student_statuses = [])
    cancelled_student_status_ids = cancelled_student_statuses.map { |ss| ss.id }
    options = { 'cancel_reason_id' => @cancel_reason_id,
                'other_reason' => @other_reason,
                'need_recalc' => @need_recalc,
                'refund_bank_account' => refund_bank_account,
                'cancelled_student_status_ids' => cancelled_student_status_ids }
    if is_redis_available?
      UserMailerWorker.perform_async(UserMailerWorker::CANCEL, @parent_status.id, options)
    else
      UserMailerWorker.new.perform(UserMailerWorker::CANCEL, @parent_status.id, options)
    end
  end

  def send_refund_email(refund_bank_account)
    UserMailer.refund_notify_internal(@parent_status, refund_bank_account, @price_diff).deliver_now
  end

  def send_payment_confirmed_email(ps)
    if is_redis_available?
      UserMailerWorker.perform_async(
        UserMailerWorker::PAYMENT_CONFIRMED, ps.id
      )
    else
      UserMailerWorker.new.perform(
        UserMailerWorker::PAYMENT_CONFIRMED, ps.id
      )
    end
  end

  def temp_ps_params
    params.require(:parent_status)
          .permit(:price, :payment_id, :learned_reason_id, :comment, :points_used)
  end

  def temp_parent_params
    params.require(:parent_status).require(:parent)
          .permit(:last_name, :first_name, :last_name_kana, :first_name_kana, :phone, :email,
                  :post_code, :prefecture, :address1, :address2, :address3, :phone2, :points)
  end

  def temp_ss_params(index)
    ss_attrs = params.require(:parent_status).require(:student_statuses_attributes)
    index_str = index.to_s

    if ss_attrs.key?(index_str)
      ss_attrs.require(index_str)
              .permit(:pc_rental, :pc_type_id, :plan_id, :course_id, :stayplan_id, :status,
                      :experience_id, :tech_holiday)
    else
      nil
    end
  end

  def temp_student_params(index)
    ss_attrs = params.require(:parent_status).require(:student_statuses_attributes)
    index_str = index.to_s

    if ss_attrs.key?(index_str)
      ss_attrs.require(index_str).require(:student_attributes)
              .permit(:first_name, :last_name, :first_name_kana, :last_name_kana,
                      :email, :phone, :allergy, :medicine, :allergy_info, :other_health,
                      :school_name, :grade, :birthday, :gender, :emergency)
    else
      nil
    end
  end

  def temp_params
    params.require(:temp)
  end

  def remove_ar_attrs(ar)
    ar.attributes.except('id', 'created_at', 'updated_at')
  end

  def parent_status_id_param
    params.require(:parent_statuses).permit(id: [])
  end

  def cancel_reason_param
    params.permit(:cancel_reason)
  end

  def other_reason_param
    params.permit(:other_reason)
  end

  def get_plan_type_name
    params.permit(:plan_type_name)[:plan_type_name]
  end

  ##
  # Builds ParentStatus from params. The ParentStatus built should be ready
  # for confirmations and payments.
  #
  def build_complete_ps(parent_id, student_ids, any_code_or_points, any_code)
    parent_status = ParentStatus.build_for_apply(
      camp_ps_params_with_parent_and_student_id
    )
    parent_status.reflect_any_code(any_code, parent_id) if any_code_or_points == 'any_code' && any_code.present?

    unless replace_parent_if_necessary(parent_status, parent_id)
      return nil
    end

    unless replace_students_if_necessary(parent_status, student_ids, parent_id)
      return nil
    end

    parent_status.parent.skip_password_verification = true

    parent_status.student_statuses.each do |ss|
      ss.student.skip_password_verification = true
    end

    parent_status.replace_with_db_coupons

    if parent_status.is_free_camp?
      parent_status.money_received = true
      parent_status.price = 0
    else
      parent_status.recalculate_price
      if parent_status.price > 0
        parent_status.money_received = false
      else
        parent_status.money_received = true
      end
    end

    parent_status
  end

  def is_current_parent?(parent_id)
    if current_parent.nil? && current_admin_user.nil?
      false
    else
      if current_admin_user
        true
      else
        parent_id == current_parent.id.to_s
      end
    end
  end

  def lookup_and_assign_parent(parent_id, attributes)
    parent = Parent.find(parent_id)
    parent.assign_attributes(attributes)
    parent
  end

  def replace_parent_if_necessary(parent_status, parent_id)
    if parent_id.present?
      unless is_current_parent?(parent_id)
        permission_denied
        return false
      end

      parent = lookup_and_assign_parent(parent_id,
                                        camp_ps_params_with_parent_and_student_id[:parent_attributes])
      parent.skip_password_verification = true
      parent_status.parent = parent
    end
    true
  end

  def replace_students_if_necessary(parent_status, student_ids, parent_id)
    if student_ids && !student_ids.empty?

      ss_list = parent_status.student_statuses
      student_ids.each do |index, student_id|
        next if student_id.blank? || student_id == 'new'

        student = Student.find(student_id)
        unless student
          permission_denied
          return false
        end

        if student.parent_id.to_s != parent_id
          permission_denied
          return false
        end

        new_attr = camp_ps_params_with_parent_and_student_id[:student_statuses_attributes][index.to_s][:student_attributes]
        student.assign_attributes(new_attr)
        student.skip_password_verification = true
        ss_list[index.to_i].student = student
      end
    end

    true
  end

  def replace_birthdays(parent_status)
    birth_years = params[:birthday_years]
    birth_months = params[:birthday_months]
    birth_days = params[:birthday_days]

    parent_status.student_statuses.each_with_index do |ss, index|
      year = birth_years[index]
      month = birth_months[index]
      day = birth_days[index]

      if year.present? && month.present? && day.present?
        ss.student.birthday = Date.new(year.to_i, month.to_i, day.to_i)
      end
    end
  end

  def check_deadline!
    if !@parent_status.changes_allowed? && !current_admin_user
      permission_denied
    end
  end

  def check_change_request_deadline!
    if !@parent_status.change_requests_allowed? && !current_admin_user
      permission_denied
    end
  end

  def check_cancels_allowed!
    if !@parent_status.cancels_allowed? && !current_admin_user
      permission_denied
    end
  end

  def is_plan_courses_active(parent_status, ss_diffs = nil)
    parent_status.student_statuses.each_with_index do |student_status, index|
      plan_course = student_status.plan_course
      plan_stayplan = student_status.plan_stayplan
      if ss_diffs.blank? || ss_diffs[index][:course_id].present?
        unless plan_course.plan.active?
          logger.error "Plan is not active #{plan_course.plan.id}"
          return false
        end
        if plan_course.plan.availability == :full
          logger.error "Plan is full #{plan_course.plan.id}"
          return false
        end
        unless plan_course.active?
          logger.error "PlanCourse is not active #{plan_course.id}"
          return false
        end
        if plan_course.capacity_status == :full
          logger.error "PlanCourse is full #{plan_course.id}"
          return false
        end
        unless plan_stayplan.is_active?
          logger.error "PlanStayplan is not active #{plan_stayplan.id}"
          return false
        end
        if plan_stayplan.capacity_status == :full
          logger.error "PlanStayplan is full #{plan_stayplan.id}"
          return false
        end
      end
    end
    return true
  end

  def check_plan_close(parent_status)
    p_ids = parent_status.plan_courses.map(&:plan_id).uniq

    p_ids.each do |p_id|
      options = { 'plan_id' => p_id }

      logger.info "Scheduling CampWorker job for Plan ID=#{p_id}"

      CampWorker.perform_async_or_default(
        CampWorker::UpdatePlanAvailability, options
      )
    end
  end

  def check_plan_course_close(parent_status)
    pc_ids = parent_status.plan_courses.map(&:id)

    pc_ids.each do |pc_id|
      options = { 'plan_course_id' => pc_id }

      logger.info "Scheduling CampWorker job for PlanCourse ID=#{pc_id}"

      CampWorker.perform_async_or_default(
        CampWorker::UpdatePlanCourseAvailability, options
      )
    end
  end

  def process_diffs
    new_ps = ParentStatus.new(camp_ps_params_all)

    old_price = calculate_price(@parent_status)[:price]
    @old_payment = @parent_status.payment

    @parent_status.copy_from_new_status new_ps
    @parent_status.payment = new_ps.payment
    new_ps.update_pending_cancel
    @parent_status.update_pending_cancel_if_necessary(new_ps)

    new_price = calculate_price(@parent_status)[:price]

    @price_diff = new_price - old_price

    logger.info "Price change: #{old_price} => #{new_price} (diff: #{@price_diff})"

    @parent_status.price = new_price

    @ps_diff = @parent_status.diff_with_db
    @ss_diffs = @parent_status.student_statuses.map(&:diff_with_db)

    if @parent_status.camp.has_multi_rental_info?
      @ss_rental_diffs = @ss_diffs.map.with_index do |ss_diff, i|
        student_status = StudentStatus.find(@parent_status.student_statuses[i].id)
        [
          student_status.student_status_camp_rentals.map(&:for_json),
          new_ps.student_statuses[i].student_status_camp_rentals.map(&:for_json)
        ]
      end
    end
    logger.info "ParentStatus diff: #{@ps_diff}, StudentStatus diff: #{@ss_diffs}"
  end

  def refund_bank_account_or_initialize
    refund_bank_account = @parent.school_refund_bank_account
    if refund_bank_account.blank?
      refund_bank_account = ParentBankAccount.new(parent: @parent, usage: ParentBankAccount.usages[:school_refund])
    end
    refund_bank_account
  end

  def parent_bank_account_params
    params.require(:parent_bank_account)
          .permit(:bank_name, :branch_name, :type_code, :number, :holder_name,
                  :holder_kana, :usage, :use_withdraw_account)
  end

  def save_edit_request_if_changes_not_allowed
    if @parent_status.changes_allowed?
      return false
    end

    if ParentStatusChangeRequest.can_change_without_request @parent_status
      return false
    end

    parent_status_change_request = ParentStatusChangeRequest.create_by_parent_status @parent_status, camp_ps_params_all
    send_change_request_email(parent_status_change_request)
    redirect_to change_request_complete_parent_status_path(@parent_status)
    return true
  end
end
