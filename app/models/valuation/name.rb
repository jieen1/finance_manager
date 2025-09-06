class Valuation::Name
  def initialize(valuation_kind, accountable_type)
    @valuation_kind = valuation_kind
    @accountable_type = accountable_type
  end

  def to_s
    case valuation_kind
    when "opening_anchor"
      opening_anchor_name
    when "current_anchor"
      current_anchor_name
    else
      recon_name
    end
  end

  private
    attr_reader :valuation_kind, :accountable_type

    def opening_anchor_name
      case accountable_type
      when "Property", "Vehicle"
        t("original_purchase_price")
      when "Loan"
        t("original_pricipal")
      when "Investment", "Crypto", "OtherAsset"
        t(".opening_account_value")
      else
        t(".opening_balance")
      end
    end

    def current_anchor_name
      case accountable_type
      when "Property", "Vehicle"
        t(".current_market_value")
      when "Loan"
        t(".current_loan_balance")
      when "Investment", "Crypto", "OtherAsset"
        t(".current_account_value")
      else
        t(".current_balance")
      end
    end

    def recon_name
      case accountable_type
      when "Property", "Investment", "Vehicle", "Crypto", "OtherAsset"
        t(".manual_value_update")
      when "Loan"
        t(".manual_principal_update")
      else
        t(".manual_balance_update")
      end
    end
end
