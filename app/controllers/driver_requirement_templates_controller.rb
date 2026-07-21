class DriverRequirementTemplatesController < ApplicationController
  load_and_authorize_resource except: [:create]
  before_action :guard_system_template_permission, except: [:index, :create]

  def index
    if params[:provider_id].blank? || (current_provider_id.to_s != params[:provider_id].to_s)
      authorize! :manage, :system_driver_requirement_template
    end

    if params[:provider_id].blank?
      @driver_requirement_templates = DriverRequirementTemplate.system_wide
    else
      @driver_requirement_templates = DriverRequirementTemplate.provider_only(params[:provider_id])
    end

    @driver_requirement_templates.order(:name, :legal)
  end

  def show
    @readonly = true
  end

  def new
  end

  def create
    @driver_requirement_template = DriverRequirementTemplate.new template_params

    @driver_requirement_template.provider_id = current_provider_id unless @is_system_template

    if @driver_requirement_template.provider_id.blank?
      authorize! :manage, :system_driver_requirement_template
    else
      authorize! :manage, @driver_requirement_template
    end

    if @driver_requirement_template.save
      redirect_to driver_requirement_template_path(@driver_requirement_template, provider_id: @driver_requirement_template.provider_id)
    else
      render 'new'
    end
  end

  def edit
  end

  def update
    if @driver_requirement_template.update template_params
      redirect_to driver_requirement_template_path(@driver_requirement_template,provider_id: @driver_requirement_template.provider_id)
    else
      render 'edit'
    end
  end

  def destroy
    !@driver_requirement_template.destroy
    redirect_to driver_requirement_templates_path(provider_id: params[:provider_id])
  end

  private

  def template_params
    params.require(:driver_requirement_template).permit(:name, :legal, :reoccuring)
  end

  def guard_system_template_permission
    if params[:provider_id].blank? && @driver_requirement_template.try(:provider_id).blank?
      authorize! :manage, :system_driver_requirement_template
      @is_system_template = true
    end
  end
end