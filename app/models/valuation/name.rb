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
        I18n.t("valuation.name.opening_anchor.property_vehicle")
      when "Loan"
        I18n.t("valuation.name.opening_anchor.loan")
      when "Investment", "Crypto", "OtherAsset"
        I18n.t("valuation.name.opening_anchor.investment")
      else
        I18n.t("valuation.name.opening_anchor.default")
      end
    end

    def current_anchor_name
      case accountable_type
      when "Property", "Vehicle"
        I18n.t("valuation.name.current_anchor.property_vehicle")
      when "Loan"
        I18n.t("valuation.name.current_anchor.loan")
      when "Investment", "Crypto", "OtherAsset"
        I18n.t("valuation.name.current_anchor.investment")
      else
        I18n.t("valuation.name.current_anchor.default")
      end
    end

    def recon_name
      case accountable_type
      when "Property", "Investment", "Vehicle", "Crypto", "OtherAsset"
        I18n.t("valuation.name.recon.property_investment")
      when "Loan"
        I18n.t("valuation.name.recon.loan")
      else
        I18n.t("valuation.name.recon.default")
      end
    end
end
