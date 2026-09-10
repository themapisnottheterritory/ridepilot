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
      return redirect_to customer_fare_account_path(@customer), alert: "Enter an amount."
    end

    tx = case p[:kind]
         when "load"
           ledger.load!(amount, payment_method: p[:payment_method], reference: p[:reference].presence, note: p[:note].presence)
         when "refund"
           ledger.refund!(amount, note: p[:note].presence || "Refund", reference: p[:reference].presence)
         when "adjust"
           ledger.adjust!(amount, note: p[:note].presence)
         else
           return redirect_to customer_fare_account_path(@customer), alert: "Unknown transaction type."
         end

    msg = "#{tx.kind_label} of #{view_context.number_to_currency(tx.amount.abs)} posted. Balance is now #{view_context.number_to_currency(tx.balance_after)}."
    if tx.load? && p[:receipt] == "1"
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
    params.require(:fare_transaction).permit(:kind, :amount, :payment_method, :reference, :note, :receipt)
  end

  def fare_transaction_params
    tx_params
  end
end
