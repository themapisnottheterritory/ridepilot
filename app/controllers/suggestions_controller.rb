# Send a suggestion (Suggestion): anyone signed in can send one and see their
# own; admins see their agency's (I.T. sees all) and mark status and reply.
class SuggestionsController < ApplicationController
  before_action { raise ActionController::RoutingError, "Not Found" unless Suggestion.enabled? }

  def index
    @manager = Suggestion.manageable_by?(current_user)
    scope = @manager ? Suggestion.visible_to(current_user, current_provider) : Suggestion.where(user_id: current_user.id)
    @counts = scope.group(:status).count
    @status = params[:status].presence_in(Suggestion::STATUSES.keys) if @manager
    @suggestions = scope.includes(:user, :provider, :help_question).newest_first
    @suggestions = @suggestions.where(status: @status) if @status
    @suggestions = @suggestions.limit(300)
  end

  def new
    @suggestion = Suggestion.new(kind: params[:kind].presence_in(Suggestion::KINDS.keys) || "idea",
                                 page_path: from_path, help_question_id: own_help_question_id)
  end

  def create
    @suggestion = Suggestion.new(params.require(:suggestion).permit(:kind, :body, :page_path, :help_question_id))
    @suggestion.help_question_id = nil unless HelpQuestion.where(user_id: current_user.id, id: @suggestion.help_question_id).exists?
    @suggestion.page_path = @suggestion.page_path.to_s.first(250).presence
    @suggestion.assign_attributes(user: current_user, provider: current_provider)
    if @suggestion.save
      begin
        SuggestionMailer.new_suggestion(@suggestion).deliver_now
      rescue StandardError => e   # it's saved and on the list either way
        Rails.logger.error("SuggestionMailer failed for suggestion #{@suggestion.id}: #{e.class}: #{e.message}")
      end
      redirect_to suggestions_path, notice: "Thank you! GCRPC I.T. has your #{@suggestion.kind == 'question' ? 'question' : 'suggestion'}. You'll see its status and any reply here."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    raise CanCan::AccessDenied unless Suggestion.manageable_by?(current_user)
    suggestion = Suggestion.visible_to(current_user, current_provider).find(params[:id])
    attrs = params.require(:suggestion).permit(:status, :reply)
    suggestion.assign_attributes(attrs)
    suggestion.replied_by = current_user if suggestion.reply_changed?
    suggestion.save!
    redirect_to suggestions_path(status: params[:return_status].presence), notice: "Saved."
  end

  private

  # the page the user came from, so the note says which screen it's about
  def from_path
    path = params[:from].presence || (URI(request.referer).path rescue nil)
    path if path.to_s.start_with?("/") && !path.include?("/suggestions")
  end

  def own_help_question_id
    HelpQuestion.where(user_id: current_user.id, id: params[:help_question_id]).pick(:id) if params[:help_question_id].present?
  end
end
