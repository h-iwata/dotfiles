class ParentsController < ApplicationController
  include Shared::Params
  include PriceDisplayHelper

  before_action :set_parent_from_id,
                only: [:edit, :update, :mypage]
  before_action :authenticate_parent!, only: :refund_bank_account_entry
  before_action :set_parent_from_current,
                only: [:confirm, :points_left, :convert_coupon, :convert_coupon, :refund_bank_account_entry]
  before_action :authenticate_current_parent_or_admin!, except: :refund_bank_account_entry
  before_action :authenticate_admin_user!, only: [:mypage]

  before_action :set_email_confirms, only: [:edit]
  before_action :set_show_email2, only: [:edit, :update]
  before_action :authenticate_admin_user!, only: [:give_points]

  # POST /parents/points_left
  def points_left
    points_used_str = params[:pointsUsed]

    if points_used_str
      points_used = points_used_str.to_i
    else
      points_used = 0
    end

    left = 0
    if current_parent
      if points_used < 0
        render json: {
          error: "NEGATIVE_POINTS_NOT_ALLOWED",
          points_left: split_with_comma(current_parent.points)
        }
        return
      end
      left = current_parent.points - points_used
      if left < 0
        render json: {
          error: "NOT_ENOUGH_POINTS",
          points_max: current_parent.points
        }
        return
      end
    end

    render json: { points_left: split_with_comma(left) }
  end

  # GET /parents/1/edit
  def edit
    @show_mail_magazine = true
  end

  # PATCH/PUT /parents/1
  # PATCH/PUT /parents/1.json
  def update
    @parent.skip_password_verification = true
    @parent.double_check_email = true
    @parent.double_check_email2 = true

    respond_to do |format|
      if @parent.update(parent_params)
        format.html { redirect_to parent_root_path }
        format.json { head :no_content }
      else
        format.html { render :edit }
        format.json { render json: @parent.errors, status: :unprocessable_entity }
      end
    end
  end

  def mypage
    @parent_statuses = ParentStatus.where(parent_id: @parent.id).order(id: 'DESC')
    @admin_current_parent = @parent
    @admin_login = true
    @body_class = 'apply-bg'
    @introduction_coupon = @parent.current_introduction_coupon
    @show_school_continue_survay = @parent.school_applications.any? { |v| v.school_season&.next_season && v.school_season.passed_survey_startline? && v.school_season.is_current? && v.survey_answered? }
    @preentry_camps = PreentryCamp.available.where.not(id: preentry_camp_parents.map { |x| x.preentry_camp.id })
    @preentry_camp_parents = PreentryCampParent.where(parent: @parent)
    cookies.delete :mypage_tab
    render 'parent_statuses/mypage'
  end

  def refund_bank_account_entry
    parent_bank_account = @parent.parent_bank_accounts.school_refund_account
    unless parent_bank_account
      redirect_to new_parent_parent_bank_account_url(@parent)
    else
      redirect_to edit_parent_parent_bank_account_url(@parent, parent_bank_account)
    end
  end

  # POST /parents/give_points
  def give_points
    points_str = points_params[:points]
    expire_at = Time.zone.local(params["parent_points"]["expire_at(1i)"].to_i,
                                params["parent_points"]["expire_at(2i)"].to_i,
                                params["parent_points"]["expire_at(3i)"].to_i,
                                params["parent_points"]["expire_at(4i)"].to_i,
                                params["parent_points"]["expire_at(5i)"].to_i)

    parent_ids = parent_ids_params[:parent_ids]
    @parents = Parent.where(id: parent_ids)

    begin
      points = Integer(points_str)
    rescue ArgumentError, TypeError
      redirect_to admin_parents_path, alert: 'ポイントが数字ではありません。'
      return
    end

    @parents.each do |parent|
      parent.add_points(points, expire_at: expire_at)
    end

    redirect_to admin_parents_path, notice: "#{points} ポイントを付与しました。"
  end

  private

  def set_parent_from_current
    unless @parent
      @parent = current_parent
    end
  end

  def set_parent_from_id
    @parent = Parent.find(params[:id])
  end

  def set_email_confirms
    @parent.set_email_confirm
  end

  def set_show_email2
    @show_email2 = true
  end

  # Never trust parameters from the scary internet, only allow the white list through.
  def parent_params
    params.require(:parent).permit(parent_attrs)
  end

  def coupon_code_param
    params.permit(:coupon_code)
  end

  def points_params
    params.permit(:points)
  end

  def parent_ids_params
    params.permit(parent_ids: [])
  end
end
