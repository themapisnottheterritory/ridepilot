class VehicleRequirementTemplatesController < ApplicationController
  load_and_authorize_resource except: [:create]
  before_action :guard_system_template_permission, except: [:index, :create]

  def index
    if params[:provider_id].blank? || (current_provider_id.to_s != params[:provider_id].to_s)
      authorize! :manage, :system_vehicle_requirement_template
    end

    if params[:provider_id].blank?
      @vehicle_requirement_templates = VehicleRequirementTemplate.system_wide
    else
      @vehicle_requirement_templates = VehicleRequirementTemplate.provider_only(params[:provider_id])
    end

    @vehicle_requirement_templates.order(:name, :legal)
  end

  def show
    @readonly = true
  end

  def new
  end

  def create
    @vehicle_requirement_template = VehicleRequirementTemplate.new template_params

    @vehicle_requirement_template.provider_id = current_provider_id unless @is_system_template

    if @vehicle_requirement_template.provider_id.blank?
      authorize! :manage, :system_vehicle_requirement_template
    else
      authorize! :manage, @vehicle_requirement_template
    end

    if @vehicle_requirement_template.save
      redirect_to vehicle_requirement_template_path(@vehicle_requirement_template, provider_id: @vehicle_requirement_template.provider_id)
    else
      render 'new'
    end
  end

  def edit
  end

  def update
    if @vehicle_requirement_template.update template_params
      redirect_to vehicle_requirement_template_path(@vehicle_requirement_template,provider_id: @vehicle_requirement_template.provider_id)
    else
      render 'edit'
    end
  end

  def destroy
    !@vehicle_requirement_template.destroy
    redirect_to vehicle_requirement_templates_path(provider_id: params[:provider_id])
  end

  private

  def template_params
    params.require(:vehicle_requirement_template).permit(:name, :legal, :reoccuring)
  end

  def guard_system_template_permission
    if params[:provider_id].blank? && @vehicle_requirement_template.try(:provider_id).blank?
      authorize! :manage, :system_vehicle_requirement_template
      @is_system_template = true
    end
  end
end