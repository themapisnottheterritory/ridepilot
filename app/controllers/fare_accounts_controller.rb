# The office side of fare cards (docs/fare-card-design.md, phase 1).
#
#   GET /fare_accounts               scan box, today's takings, every rider with a card or a balance
#   GET /fare_accounts/lookup?q=     what the reader typed (or a serial, or a name) -> the rider's account
#   GET /customers/:id/fare_account  one rider: balance, tokens, ledger, load / adjust / issue forms
#
# Writes go through FareTokensController and FareTransactionsController.
class FareAccountsController < ApplicationController
  before_action :authorize_fare_accounts

  def index
    scope = Customer.for_provider(current_provider_id).accessible_by(current_ability)
    @accounts = scope.where("customers.fare_balance <> 0 OR customers.fare_pass_expires_on IS NOT NULL OR customers.id IN (SELECT customer_id FROM fare_tokens WHERE deleted_at IS NULL)")
                     .includes(:fare_tokens)
    @accounts = @accounts.by_term(params[:term].downcase) if params[:term].present?
    @accounts = @accounts.paginate(page: params[:page], per_page: 50)

    @outstanding = scope.sum(:fare_balance)
    @accounts_count = scope.where("customers.fare_balance <> 0 OR customers.id IN (SELECT customer_id FROM fare_tokens WHERE deleted_at IS NULL)").count
    @active_tokens = FareToken.for_provider(current_provider_id).active.count

    day = Time.zone.now.beginning_of_day
    todays = FareTransaction.for_provider(current_provider_id).recorded_between(day, day + 1.day)
    @today_loads  = todays.loads.group(:payment_method).sum(:amount)
    @today_fares  = todays.where(kind: "debit").sum(:amount).abs
    @today_count  = todays.loads.count
  end

  # One box for everything: a card tapped on the office reader (types the UID
  # and Enter), a serial number typed from the card face, or a rider's name.
  def lookup
    q = params[:q].to_s.strip
    return redirect_to(fare_accounts_path) if q.blank?

    token = FareToken.for_provider(current_provider_id).lookup(q)
    token ||= FareToken.for_provider(current_provider_id).find_by(serial: q.sub(/\A#/, ""))
    if token
      notice = case token.status
               when "active" then nil
               else "This card is marked #{token.status}."
               end
      return redirect_to customer_fare_account_path(token.customer, token_id: token.id), alert: notice
    end

    matches = Customer.for_provider(current_provider_id).accessible_by(current_ability).by_term(q.downcase).limit(2).to_a
    if matches.size == 1
      redirect_to customer_fare_account_path(matches.first)
    elsif matches.size > 1
      redirect_to fare_accounts_path(term: q)
    else
      # Looks like a card the reader just typed, but nobody owns it: offer to issue it.
      if q.length >= 6 && q !~ /\s/
        redirect_to fare_accounts_path(unknown_uid: FareToken.normalize_uid(q)),
                    alert: "No card with UID #{FareToken.normalize_uid(q)}. Open a rider's account to issue it."
      else
        redirect_to fare_accounts_path(term: q), alert: "No rider or card matched \"#{q}\"."
      end
    end
  end

  def show
    @customer = Customer.for_provider(current_provider_id).find(params[:id])
    authorize! :read, @customer
    @tokens = @customer.fare_tokens.for_provider(current_provider_id).default_order.to_a
    @transactions = @customer.fare_transactions.newest_first.includes(:fare_token, :recorded_by, :driver, :run, :trip)
                             .paginate(page: params[:page], per_page: 25)
    @highlight_token_id = params[:token_id].to_i
    @new_token = FareToken.new(kind: "rfid", uid: params[:uid])
    @ledger = FareLedger.new(@customer, provider: current_provider)
    @can_write = can?(:create, FareTransaction)
    @rider_categories = RiderCategory.by_provider(current_provider).default_order
  end

  # Rider category (drives the fixed-route fare on a tap), pass expiry and a
  # per-rider floor. Plain customer columns, kept off the big customer form.
  def update
    @customer = Customer.for_provider(current_provider_id).find(params[:id])
    authorize! :update, @customer
    attrs = params.require(:customer).permit(:default_rider_category_id, :fare_pass_expires_on, :fare_balance_floor)
    attrs[:fare_balance_floor] = attrs[:fare_balance_floor].presence
    attrs[:fare_pass_expires_on] = attrs[:fare_pass_expires_on].presence
    attrs[:default_rider_category_id] = attrs[:default_rider_category_id].presence
    if @customer.update(attrs)
      redirect_to customer_fare_account_path(@customer), notice: "Fare settings saved."
    else
      redirect_to customer_fare_account_path(@customer), alert: "Not saved: #{@customer.errors.full_messages.to_sentence}"
    end
  end

  private

  def authorize_fare_accounts
    authorize! :read, FareToken
  end
end
