# Issue a card or QR to a rider, and change its status (lost / blocked /
# reactivated / retired). The balance never moves here; it lives on the
# customer and follows them to a replacement token.
class FareTokensController < ApplicationController
  load_and_authorize_resource :customer, only: :create
  load_and_authorize_resource :fare_token, only: :update

  def create
    @fare_token = @customer.fare_tokens.build(token_params)
    @fare_token.provider_id = current_provider_id
    @fare_token.issued_by = current_user
    authorize! :create, @fare_token

    if @fare_token.save
      redirect_to customer_fare_account_path(@customer, token_id: @fare_token.id),
                  notice: "#{@fare_token.kind_label} #{@fare_token.label} issued to #{@customer.name}."
    else
      redirect_to customer_fare_account_path(@customer, uid: token_params[:uid]),
                  alert: "Not issued: #{@fare_token.errors.full_messages.to_sentence}"
    end
  end

  def update
    status = params[:status].to_s
    unless FareToken::STATUSES.include?(status)
      return redirect_to customer_fare_account_path(@fare_token.customer), alert: "Unknown status."
    end
    PaperTrail.request(whodunnit: current_user.id.to_s) do
      @fare_token.update!(status: status, note: [@fare_token.note, params[:note].presence].compact.join(" | ").presence)
    end
    redirect_to customer_fare_account_path(@fare_token.customer, token_id: @fare_token.id),
                notice: "#{@fare_token.label} is now #{status}."
  end

  private

  def token_params
    params.require(:fare_token).permit(:kind, :uid, :serial, :note)
  end

  def fare_token_params
    token_params
  end
end
