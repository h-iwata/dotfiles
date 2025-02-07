class PreentryCampParentController < ApplicationController
  layout 'new_camp_apply'
  Steps = Struct.new(:current, :last)

  def new
    @preentry_camp = PreentryCamp.find(params[:preentry_camp_id])
    @preentry_camp_parent = PreentryCampParent.new
    @is_new_parent = !current_parent
    if !@is_new_parent
      # TODO: プレエントリー申し込み済みの処理
      @preentry_camp_parent.parent = current_parent
    else
      @preentry_camp_parent.build_parent
    end
    if params.key? :preentry_camp_parent
      @preentry_camp_parent.assign_attributes(params.require(:preentry_camp_parent).permit(preentry_camp_parent_attrs))
    end
    render :new, locals: { steps: Steps.new(1, 3) }
  end

  def confirm
    @preentry_camp = PreentryCamp.find(params[:preentry_camp_id])
    @preentry_camp_parent = PreentryCampParent.new(
      params.require(:preentry_camp_parent)
            .permit(preentry_camp_parent_attrs)
    )
    @preentry_camp_parent.preentry_camp = @preentry_camp
    @is_new_parent = !current_parent
    unless @is_new_parent
      @preentry_camp_parent.parent = current_parent
    end
    if @preentry_camp_parent.invalid?
      render :new, locals: { steps: Steps.new(1, 3) }
    else
      render :confirm, locals: { steps: Steps.new(2, 3) }
    end
  end

  def create
    @preentry_camp = PreentryCamp.find(params[:preentry_camp_id])
    @preentry_camp_parent = PreentryCampParent.new(
      params.require(:preentry_camp_parent)
            .permit(preentry_camp_parent_attrs)
    )
    @preentry_camp_parent.preentry_camp = @preentry_camp
    @preentry_camp_parent.parent = current_parent if current_parent
    begin
      ActiveRecord::Base.transaction do
        # @preentry_camp_parent.save!
      end
      UserMailer.preentry_notify(@preentry_camp_parent).deliver_later
    rescue StandardError => e
      logger.error "Preentry Error: #{e}"
      logger.error e.backtrace.join("\n")
      @error = OpenStruct.new({ errors: OpenStruct.new({ full_messages: ["Preentry Error: #{e}"] }) })
      pp error.errors.full_messages
      render :new, locals: { steps: Steps.new(1, 3) } and return
    end
    redirect_to finished_preentry_camp_preentry_camp_parent_index_path(@preentry_camp, preentry_camp_parent_id: @preentry_camp_parent.id) and return
  end

  def finished
    @preentry_camp = PreentryCamp.find(params[:preentry_camp_id])
    render :finished, locals: { steps: Steps.new(3, 3) }
  end
end
