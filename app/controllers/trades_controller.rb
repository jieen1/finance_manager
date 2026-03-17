class TradesController < ApplicationController
  include EntryableResource

  # Defaults to a buy trade
  def new
    @account = Current.family.accounts.find_by(id: params[:account_id])
    @model = Current.family.entries.new(
      account: @account,
      currency: @account ? @account.currency : Current.family.currency,
      entryable: Trade.new
    )
  end

  # Can create a trade, transaction (e.g. "fees"), or transfer (e.g. "withdrawal")
  def create
    @account = Current.family.accounts.find(params[:account_id])
    @model = Trade::CreateForm.new(create_params.merge(account: @account)).create

    if @model.persisted?
      @model.sync_account_later if @model.respond_to?(:sync_account_later)
      flash[:notice] = t("entries.create.success")

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@account) }
        format.turbo_stream { stream_redirect_back_or_to account_path(@account) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def update
    if @entry.update(update_entry_params)
      @entry.sync_account_later

      respond_to do |format|
        format.html { redirect_back_or_to account_path(@entry.account), notice: t("entries.update.success") }
        format.turbo_stream do
          render turbo_stream: [
            turbo_stream.replace(
              "header_entry_#{@entry.id}",
              partial: "trades/header",
              locals: { entry: @entry }
            ),
            turbo_stream.replace("entry_#{@entry.id}", partial: "entries/entry", locals: { entry: @entry })
          ]
        end
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private
    def convert_to_account_currency(amount, from_currency, date)
      return amount if from_currency == @entry.account.currency
      rate = ExchangeRate.find_or_fetch_rate(from: from_currency, to: @entry.account.currency, date: date)&.rate
      rate ? amount * rate : amount
    end

    def entry_params
      params.require(:entry).permit(
        :name, :date, :amount, :currency, :excluded, :notes, :nature,
        entryable_attributes: [ :id, :qty, :price, :fee, :fee_currency ]
      )
    end

    def create_params
      params.require(:model).permit(
        :date, :amount, :currency, :qty, :price, :fee, :fee_currency, :ticker, :manual_ticker, :type, :transfer_account_id
      )
    end

    def update_entry_params
      return entry_params unless entry_params[:entryable_attributes].present?

      update_params = entry_params
      update_params = update_params.merge(entryable_type: "Trade")

      qty = update_params[:entryable_attributes][:qty]
      price = update_params[:entryable_attributes][:price]
      fee = update_params[:entryable_attributes][:fee] || 0

      if qty.present? && price.present?
        qty = update_params[:nature] == "inflow" ? -qty.to_d : qty.to_d
        update_params[:entryable_attributes][:qty] = qty

        # Default fee_currency to entry currency if not provided
        if fee.to_d > 0 && update_params[:entryable_attributes][:fee_currency].blank?
          update_params[:entryable_attributes][:fee_currency] = update_params[:currency] || @entry.currency
        end

        # entry.amount = actual cash flow in account currency
        trade_currency = @entry.entryable.currency || @entry.currency
        fee_currency_val = update_params[:entryable_attributes][:fee_currency] || @entry.entryable.fee_currency || trade_currency
        base_in_account = convert_to_account_currency(qty * price.to_d, trade_currency, @entry.date)
        fee_in_account = convert_to_account_currency(fee.to_d, fee_currency_val, @entry.date)
        update_params[:amount] = base_in_account + fee_in_account
        update_params[:currency] = @entry.account.currency
      end

      update_params.except(:nature)
    end
end
