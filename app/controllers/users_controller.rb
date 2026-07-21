require 'new_user_mailer'

class UsersController < ApplicationController
  load_and_authorize_resource :provider, only: [:new_user, :create_user]
  before_action :set_user, only: [:show, :edit, :update, :reset_password]
  skip_before_action :authenticate_user!, only: [:new_user, :create_user, :get_verification_question, :answer_verification_question], raise: false

  def new_user
    authorize! :edit, @provider
    @user = User.new
    @errors = []
  end

  def create_user
    authorize! :edit, @provider
    
    @user = User.only_deleted.find_by_username(params[:user][:username])
    @is_user_deleted = @user.try(:deleted?)
    if !@is_user_deleted
      #this user might already be a member of the site, but not of this
      #provider, in which case we ought to just set up the role
      @user = User.find_by_username(params[:user][:username])
      @role = Role.new
      new_password = nil
      new_user = false
      record_valid = false
      User.transaction do
        begin
          new_attrs = user_params
          is_address_blank = check_blank_address
          if is_address_blank
            new_attrs = new_attrs.except(:user_address_attributes)
          end

          if not @user
            @user = User.new(new_attrs)
            @user.user_address = nil if is_address_blank
            @user.password = User.generate_password
            raw, enc = Devise.token_generator.generate(User, :reset_password_token)
            @user.reset_password_token = enc
            @user.reset_password_sent_at = Time.zone.now.utc
            @user.current_provider = @provider
            @user.save!
            new_user = true
          end

          @role.user = @user
          @role.provider = @provider
          @role.level = params[:role][:level] if params[:role].present? && params[:role][:level].present?
          @role.save!

          edit_verification_questions

          record_valid = true
        rescue => e
          Rails.logger.info(e)
          raise ActiveRecord::Rollback
        end
      end

      if record_valid
        # NewUserMailer doesn't server the purpose by design
        #NewUserMailer.new_user_email(@user, new_password).deliver if new_user

        # send password reset instructions instead
        #@user.send_reset_password_instructions   if new_user

        flash.now[:notice] = "%s has been added and the instructions has been emailed" % @user.email
        redirect_to users_provider_path(@provider)
      else
        user_errors = @user.valid? ? {} : @user.errors.messages

        role_errors = @role.valid? ? {} : @role.errors.messages
        @errors = user_errors.merge(role_errors)
        render :action => :new_user
      end
    else # deleted user
      flash.now[:alert] = TranslationEngine.translate_text(:user_was_deleted)
      @errors = {}
      render :action => :new_user
    end
  end

  def show
    authorize! :read, @user
    @provider = @user.current_provider
  end

  def edit
    authorize! :edit, @user
    @provider = @user.current_provider
  end

  def update
    new_attrs = user_params
    is_address_blank = check_blank_address
    if is_address_blank
      prev_address = @user.user_address
      @user.address_id = nil
      new_attrs = new_attrs.except(:user_address_attributes)
    end
    
    if @user.update(new_attrs)
      role = Role.find_by(user: @user, provider: current_provider)
      if role && params[:role].present? && params[:role][:level].present?
        role.update(level: params[:role][:level]) 
      end

      prev_address.destroy if is_address_blank && prev_address.present?
      edit_verification_questions
      flash.now[:notice] = "User updated."
      redirect_to user_path(@user)
    else
      flash.now[:notice] = "Unable to update user."

      render :edit
    end
  end

  def show_reset_password
    @user = User.find_by_id(params[:id])
    authorize! :manage, @user
  end

  def reset_password
    
    @user = User.find(params[:id])
    authorize! :manage, @user

    @user.assign_attributes reset_password_params
    if @user.save
      if @user == current_user
        bypass_sign_in(@user)
      end

      flash.now[:notice] = "Password reset"
      redirect_to @user
    else
      flash.now[:alert] = "Error resetting password"
      render :action=>:show_reset_password
    end
  end
  
  def show_change_password
    @user = current_user
  end

  def change_password
    if current_user.update_password(change_password_params)
      bypass_sign_in(current_user)
      flash.now[:notice] = "Password changed"
      redirect_to root_path
    else
      flash.now[:alert] = "Error updating password"
      render :action=>:show_change_password
    end
  end

  # Phase 2 (O365 SSO): let a user disconnect their own linked Microsoft
  # account. Password login is always available, so this never locks anyone out.
  def unlink_entra
    current_user.update_columns(omniauth_provider: nil, omniauth_uid: nil)
    redirect_to user_path(current_user),
                notice: "Your Microsoft account has been unlinked."
  end

  def show_change_email
    @user = User.find_by_id(params[:id])
    authorize! :manage, @user
  end

  def change_email
    @user = User.find(params[:id])
    authorize! :manage, @user

    if @user.update_email(change_email_params)
      if @user == current_user
        bypass_sign_in(current_user)
      end

      flash.now[:notice] = "Email changed"
      redirect_to users_provider_path(current_provider)
    else
      flash.now[:alert] = "Error updating email"
      render :action=>:show_change_email
    end
  end

  def show_change_expiration
    @user = User.find(params[:id])
    authorize! :manage, @user
  end

  def change_expiration
    @user = User.find(params[:id])
    authorize! :manage, @user
    
    if @user.update(change_expiration_params)
      flash.now[:alert] = "Expiration set"
      redirect_to users_provider_path(@user.current_provider)
    else
      flash.now[:alert] = "Error setting expiration"
      render action: :show_change_expiration
    end
  end

  def change_provider
    is_on_provider_page = request.referrer == provider_url(current_provider)
    provider = Provider.find(params[:provider_id])
    if can? :read, provider
      current_user.current_provider = provider
      current_user.save!
    end

    if is_on_provider_page
      redirect_to provider_path(provider)
    else
      redirect_back(fallback_location: root_path)
    end
  end

  def check_session
    last_request_at = session['warden.user.user.session']['last_request_at']
    timeout_time = last_request_at + Rails.configuration.devise.timeout_in.to_i
    timeout_in = timeout_time - Time.current.to_i
    render :json => {
      'last_request_at' => last_request_at,
      'timeout_in' => timeout_in,
    }
  end

  def touch_session
    render plain: 'OK'
  end

  def restore
    @user = User.only_deleted.find_by_id(params[:id])

    @user.restore(recursive: true) if @user

    if !@user.deleted_at
      flash.now[:notice] = TranslationEngine.translate_text(:user_been_restored)
      redirect_to users_provider_path(current_provider)
    else
      flash.now[:alert] = TranslationEngine.translate_text(:unknown_error)
      redirect_back(fallback_location: user_path(@user))
    end
  end
  
  # Presents a user with a random verification question
  def get_verification_question    
    @user = User.find_by(username: get_verification_question_params[:username].downcase)
                
    if @user
      @question = @user.random_verification_question
    end
    
    unless @user && @question
      flash[:alert] = TranslationEngine.translate_text(:no_verification_questions_set)
      redirect_back(fallback_location: root_path)
    end
  end
  
  # Determine's if an answer to a verification question is correct, and if so forwards
  # on to the password reset page
  def answer_verification_question
    @user = User.find_by_id(params[:id])
    @question = @user.verification_questions.find_by_id(answer_verification_question_params[:verification_question_id])
    if @question.correct?(answer_verification_question_params[:answer])
      bypass_sign_in(@user)
      redirect_to action: :show_reset_password, id: @user.id
    else
      flash[:alert] = TranslationEngine.translate_text(:verification_question_incorrect_answer)
      redirect_to action: :get_verification_question, user: {username: @user.username}
    end
  end

  private
  
  def user_params
    params.require(:user).permit(
      :email, 
      :first_name, 
      :last_name, 
      :username, 
      :phone_number, 
      :user_address_attributes => [
        :address,
        :building_name,
        :city,
        :name,
        :provider_id,
        :state,
        :zip,
        :notes
      ])
  end
  
  def get_verification_question_params
    params.require(:user).permit(:username)
  end
  
  def answer_verification_question_params
    params.require(:answer_verification_question).permit(:answer, :verification_question_id)
  end

  def set_user
    @user = User.find_by_id(params[:id])
  end
  
  def change_expiration_params
    params.require(:user).permit(:expires_at, :inactivation_reason)
  end
  
  def change_password_params
    params.require(:user).permit(:current_password, :password, :password_confirmation)
  end

  def reset_password_params
    params.require(:user).permit(:password, :password_confirmation)
  end

  def change_email_params
    params.require(:user).permit(:email)
  end

  def check_blank_address
    address_params = user_params[:user_address_attributes]
    is_blank = true
    address_params.keys.each do |key|
      next if key.to_s == 'provider_id'
      unless address_params[key].blank?
        is_blank = false
        break
      end
    end if address_params

    is_blank
  end
  
  def edit_verification_questions
    if params[:verification_questions]
      verification_questions = JSON.parse(params[:verification_questions], symbolize_names: true)
      @user.edit_verification_questions(verification_questions)
    end
  end
end
