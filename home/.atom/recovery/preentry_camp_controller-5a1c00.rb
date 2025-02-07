class PreentryCampController < ApplicationController
  layout 'new_camp_apply'

  before_action :authenticate_parent!, only: [:show_logged_in]
  before_action :check_in_progress?, only: [:show]

  def show
    @preentry_camp = PreentryCamp.find(params[:id])

    if @preentry_camp.in_progress? && parent_signed_in?
      # TODO: すでに申し込み済の処理
      redirect_to new_preentry_camp_preentry_camp_parent_path(@preentry_camp)
    end
  end

  def show_logged_in
    if parent_signed_in?
      @preentry_camp = PreentryCamp.find(params[:preentry_camp_id])
      redirect_to new_preentry_camp_preentry_camp_parent_path(@preentry_camp)
    end
  end
end
