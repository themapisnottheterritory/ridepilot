# Office postings to a rider's fare ledger: a load (cash or check taken at
# the desk), a refund, or a signed adjustment with a reason. Fares taken at
# the door come through the driver API, not here. Also renders a receipt.
class FareTransactionsController < ApplicationController
  load_and_authorize_resource :customer, only: :create
  load_and_authorize_resource :fare_transaction, only: :show

  def create
    authorize! :create, FareTransaction
    p = tx_params
    ledger = FareLedger.new(@customer, by: current_user, provider: current_provider)
    amount = BigDecimal(p[:amount].to_s.gsub(/[$,\s]/, "")) rescue nil
    if amount.nil? || amount.zero?
      return redirect_to customer_fare_account_path(@customer), alert: "Enter an amount." unless p[:kind].to_s.start_with?("pass_")
    end

    tx = case p[:kind]
         when "pass_10", "pass_20"
           category = rider_category_for(@customer)
           trips = (p[:kind] == "pass_10" ? 10 : 20)
           ledger.sell_trip_pass!(trips: trips, fare_each: category&.default_fare.to_d, category_name: category&.name,
                                  discount_pct: (trips == 10 ? current_provider.fare_pass_10_discount_pct : current_provider.fare_pass_20_discount_pct),
                                  payment_method: p[:payment_method], reference: p[:reference].presence)
         when "pass_monthly"
           through = monthly_pass_through(p[:pass_month])
           ledger.sell_monthly_pass!(price: current_provider.monthly_pass_price_for(rider_category_for(@customer)), through: through,
                                     payment_method: p[:payment_method], reference: p[:reference].presence)
         when "load"
           ledger.load!(amount, payment_method: p[:payment_method], reference: p[:reference].presence, note: p[:note].presence)
         when "refund"
           ledger.refund!(amount, note: p[:note].presence || "Refund", reference: p[:reference].presence)
         when "adjust"
           ledger.adjust!(amount, note: p[:note].presence)
         else
           return redirect_to customer_fare_account_path(@customer), alert: "Unknown transaction type."
         end

    msg = if tx.pass?
            "Monthly pass sold through #{@customer.reload.fare_pass_expires_on.strftime('%m/%d/%Y')} for #{view_context.number_to_currency(tx.amount.abs)}."
          else
            "#{tx.note.presence || tx.kind_label} #{view_context.number_to_currency(tx.amount.abs)} posted. Balance is now #{view_context.number_to_currency(tx.balance_after)}."
          end
    if (tx.load? || tx.pass?) && p[:receipt] == "1"
      redirect_to fare_transaction_path(tx), notice: msg
    else
      redirect_to customer_fare_account_path(@customer, tx_id: tx.id), notice: msg
    end
  rescue ActiveRecord::RecordInvalid => e
    redirect_to customer_fare_account_path(@customer), alert: "Not posted: #{e.record.errors.full_messages.to_sentence}"
  rescue FareLedger::Error => e
    redirect_to customer_fare_account_path(@customer), alert: "Not posted: #{e.message}"
  end

  # Printable receipt for a load.
  def show
    @customer = @fare_transaction.customer
    render layout: "pdf"
  end

  private

  def tx_params
    params.require(:fare_transaction).permit(:kind, :amount, :payment_method, :reference, :note, :receipt, :pass_month)
  end

  def rider_category_for(customer)
    visible = RiderCategory.by_provider(current_provider)
    (customer.default_rider_category_id && visible.find_by(id: customer.default_rider_category_id)) || visible.default_order.first
  end

  # "this" month, or "next"; a pass bought in the last week of a month
  # defaults to next month on the form.
  def monthly_pass_through(choice)
    base = Date.current
    base = base.next_month if choice.to_s == "next"
    base.end_of_month
  end

  def fare_transaction_params
    tx_params
  end
end
