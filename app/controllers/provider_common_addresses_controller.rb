require 'open-uri'

class ProviderCommonAddressesController < AddressesController
  before_action :set_address, :only => [:edit, :update, :destroy]
  authorize_resource

  def autocomplete
    term = parse_search_term

    #three ways to match:
    #- name
    #- building name
    #- substring of textified address (split at comma into address,
    #  city/state/zip)

    address, city_state_zip = term.split(",")
    address.strip!
    if city_state_zip
      city_state_zip.strip!
    else
      city_state_zip = ''
    end

    addresses = ProviderCommonAddress.where(provider_id: current_provider_id)
      .where('inactive is NULL or inactive != ?', true)
      .where(["((LOWER(address) like '%' || ? || '%' ) and  (city || ', ' || state || ' ' || zip like ? || '%')) or LOWER(building_name) like '%' || ? || '%' or LOWER(name) like '%' || ? || '%' ", address, city_state_zip, term, term])


    if params[:exclude].present?
      addresses = addresses.where.not(id: params[:exclude].split(','))
    end

    if addresses.size > 0

      #there are some existing addresses
      address_json = addresses.map { |address| address.json }

      address_json << Address::NewAddressOption unless request.env["HTTP_REFERER"].try(:match, /addresses\/[0-9]+\/edit/)

      render :json => address_json
    else
      #no existing addresses
      return render :json => [Address::NewAddressOption]
    end
  end

  def edit; end
  
  # create provider common address
  def create
    the_geom       = process_geom
    prefix         = params['prefix'] || ""

    new_params = address_params

    new_params[:provider_id] = current_provider_id
    new_params[:the_geom]    = the_geom if the_geom

    if params[:address_id].present?
      address = ProviderCommonAddress.find(params[:address_id])
      authorize! :edit, address
      address.attributes = new_params
    else
      new_params[:customer_id] = params[:customer_id] if params[:customer_id].present?
      authorize! :new, ProviderCommonAddress
      address = ProviderCommonAddress.new(new_params)
    end
    if address.save
      attrs = address.attributes
      attrs[:label] = address.text.gsub(/\s+/, ' ')
      attrs[:prefix] = prefix
      render json: attrs.to_json 
    else
      errors = address.errors.messages
      errors['prefix'] = prefix
      render json: errors
    end
  end

  def search
    @term      = params[:name].downcase
    @provider  = Provider.find params[:provider_id]
    @addresses = ProviderCommonAddress.accessible_by(current_ability).for_provider(@provider).where(customer_id: nil).order(:address, :name).search_for_term(@term)

    respond_to do |format|
      format.json { render :plain => render_to_string(:partial => "results.html") }
    end
  end

  def update
    new_addr_params = address_params.except(:provider_id) # don't want to overwrite provider
    the_geom       = process_geom
    new_addr_params[:the_geom] = the_geom if the_geom
    
    if @address.update new_addr_params
      flash.now[:notice] = "Address '#{@address.name}' was successfully updated"
      redirect_to addresses_provider_path(@address.provider)
    else
      render :action => :edit
    end
  end

  def destroy
    if @address.trips.present?
      if new_address = @address.replace_with!(params[:address_id])
        redirect_to addresses_provider_path(new_address.provider), :notice => "Address #{@address.name} was successfully replaced with new address #{new_address.name}."
      else
        redirect_to edit_provider_common_address_path(@address), :notice => "Address #{@address.name} can't be deleted without associating trips with another address."
      end
    else
      @address.destroy
      redirect_to addresses_provider_path(current_provider), :notice => "Address #{@address.name} was successfully deleted."
    end
  end

  def check_loading_status
    status = {
      is_loading: current_provider.address_upload_flag.is_loading 
    }

    status[:summary] = TranslationEngine.translate_text(:address_file_uploaded) if !status[:is_loading]

    render json: status
  end

  def upload
    error_msgs = []

    if !can?(:load, ProviderCommonAddress)
      error_msgs << TranslationEngine.translate_text(:not_authorized)
    else
      address_file = params[:address][:file] if params[:address]
      
      if !address_file.nil?
        if File.extname(address_file.original_filename) != '.csv'
          error_msgs << TranslationEngine.translate_text(:address_file_should_be_csv)
        elsif current_provider.address_upload_flag.is_loading
          error_msgs << TranslationEngine.translate_text(:address_file_being_uploading)
        else
          begin
            if defined?(S3_BUCKET) && S3_BUCKET
            # Make an object in your bucket for your upload
              s3_file = S3_BUCKET.object("/provider_addresses/" + address_file.original_filename)
              # Upload the file
              s3_file.put(body: address_file, acl: 'public-read')

              file_url = s3_file.public_url
            else
              file_url = address_file.path
            end

            AddressUploadWorker.perform_async(file_url, current_provider.id) #sidekiq needs to run
          rescue Exception => ex
            current_provider.address_upload_flag.uploaded!
            error_msgs << ex.message
          end
        end
      else
        error_msgs << TranslationEngine.translate_text(:select_address_file_to_upload)
      end
    end

    if error_msgs.size > 0
      full_error_msg = error_msgs.join(' ')
    end

    respond_to do |format|
      format.js
      format.html {redirect_to addresses_provider_path(current_provider), alert: full_error_msg }
    end
  end

  private
  
  def set_address
    @address = ProviderCommonAddress.find_by_id(params[:id])
  end  

  def process_geom
    if !params[:lat].blank? && !params[:lon].blank?
      Address.compute_geom(params[:lat], params[:lon])
    elsif !params[:address_lat].blank? && !params[:address_lon].blank?
      Address.compute_geom(params[:address_lat], params[:address_lon])
    else
      nil 
    end
  end

  def address_params
    params.require(:provider_common_address).permit(:address_group_id, :name, :building_name, :address, :city, :state, :zip, :in_district, :provider_id, :phone_number, :inactive, :trip_purpose_id, :notes)
  end
end
