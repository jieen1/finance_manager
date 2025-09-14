class Trade::CreateForm
  include ActiveModel::Model

  attr_accessor :account, :date, :amount, :currency, :qty,
                :price, :fee, :fee_currency, :ticker, :manual_ticker, :type, :transfer_account_id

  # Either creates a trade, transaction, or transfer based on type
  # Returns the model, regardless of success or failure
  def create
    case type
    when "buy", "sell"
      create_trade
    when "interest"
      create_interest_income
    when "deposit", "withdrawal"
      create_transfer
    end
  end

  private

    def calculate_fee_impact(signed_qty, fee_amount, fee_currency_value)
      # If fee and price use same currency, calculate directly
      if fee_currency_value == currency
        signed_qty.positive? ? fee_amount : -fee_amount
      else
        # If different currencies, need currency conversion
        converted_fee = convert_currency(fee_amount, fee_currency_value, currency, date)
        signed_qty.positive? ? converted_fee : -converted_fee
      end
    end

    def convert_currency(amount, from_currency, to_currency, date)
      # Implement currency conversion logic
      # Use existing ExchangeRate model
      return amount if from_currency == to_currency
      
      rate = ExchangeRate.find_or_fetch_rate(
        from: from_currency, 
        to: to_currency, 
        date: date
      )&.rate
      
      return amount unless rate
      amount * rate
    end

    # Users can either look up a ticker from our provider (Synth) or enter a manual, "offline" ticker (that we won't fetch prices for)
    def security
      ticker_symbol, exchange_operating_mic = ticker.present? ? ticker.split("|") : [ manual_ticker, nil ]

      Security::Resolver.new(
        ticker_symbol,
        exchange_operating_mic: exchange_operating_mic
      ).resolve
    end

    def create_trade
      signed_qty = type == "sell" ? -qty.to_d : qty.to_d
      fee_amount = fee.present? ? fee.to_d : 0
      fee_currency_value = fee_currency.present? ? fee_currency : currency
      
      # Fee calculation: for buys (positive qty) fee increases cost, for sells (negative qty) fee reduces proceeds
      base_amount = signed_qty * price.to_d
      fee_impact = calculate_fee_impact(signed_qty, fee_amount, fee_currency_value)
      signed_amount = base_amount + fee_impact

      trade_entry = account.entries.new(
        name: Trade.build_name(type, qty, security.ticker),
        date: date,
        amount: signed_amount,
        currency: currency,
        entryable: Trade.new(
          qty: signed_qty,
          price: price,
          fee: fee_amount,
          currency: currency,
          fee_currency: fee_currency_value,
          security: security
        )
      )

      if trade_entry.save
        trade_entry.lock_saved_attributes!
        account.sync_later
      end

      trade_entry
    end

    def create_interest_income
      signed_amount = amount.to_d * -1

      entry = account.entries.build(
        name: "Interest payment",
        date: date,
        amount: signed_amount,
        currency: currency,
        entryable: Transaction.new
      )

      if entry.save
        entry.lock_saved_attributes!
        account.sync_later
      end

      entry
    end

    def create_transfer
      if transfer_account_id.present?
        from_account_id = type == "withdrawal" ? account.id : transfer_account_id
        to_account_id = type == "withdrawal" ? transfer_account_id : account.id

        Transfer::Creator.new(
          family: account.family,
          source_account_id: from_account_id,
          destination_account_id: to_account_id,
          date: date,
          amount: amount
        ).create
      else
        create_unlinked_transfer
      end
    end

    # If user doesn't provide the reciprocal account, it's a regular transaction
    def create_unlinked_transfer
      signed_amount = type == "deposit" ? amount.to_d * -1 : amount.to_d

      entry = account.entries.build(
        name: signed_amount < 0 ? "Deposit to #{account.name}" : "Withdrawal from #{account.name}",
        date: date,
        amount: signed_amount,
        currency: currency,
        entryable: Transaction.new
      )

      if entry.save
        entry.lock_saved_attributes!
        account.sync_later
      end

      entry
    end
end
