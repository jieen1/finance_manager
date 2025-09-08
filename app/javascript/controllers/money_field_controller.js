import { Controller } from "@hotwired/stimulus";
import { CurrenciesService } from "services/currencies_service";

// Connects to data-controller="money-field"
// when currency select change, update the input value with the correct placeholder and step
export default class extends Controller {
  static targets = ["amount", "currency", "symbol"];
  static values = { precision: Number };

  connect() {
    this.customPrecision = this.precisionValue || null;
  }

  handleCurrencyChange(e) {
    const selectedCurrency = e.target.value;
    this.updateAmount(selectedCurrency);
  }

  updateAmount(currency) {
    new CurrenciesService().get(currency).then((currencyData) => {
      this.amountTarget.step = currencyData.step;

      if (Number.isFinite(this.amountTarget.value)) {
        // 使用自定义精度或货币的默认精度
        const precision = this.customPrecision !== null ? this.customPrecision : currencyData.default_precision;
        this.amountTarget.value = Number.parseFloat(
          this.amountTarget.value,
        ).toFixed(precision);
      }

      this.symbolTarget.innerText = currencyData.symbol;
    });
  }
}
