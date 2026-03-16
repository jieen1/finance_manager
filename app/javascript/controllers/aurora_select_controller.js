import { Controller } from "@hotwired/stimulus";

// Custom dropdown to replace native <select> with styled Aurora dropdown.
// Dropdown is appended to document.body with fixed positioning to avoid
// overflow:hidden clipping from parent containers like .aurora-card.
export default class extends Controller {
  static targets = ["select"];

  _trigger = null;
  _dropdown = null;

  connect() {
    this._buildCustomDropdown();
    document.addEventListener("click", this._handleOutsideClick);
    window.addEventListener("scroll", this._reposition, true);
  }

  disconnect() {
    document.removeEventListener("click", this._handleOutsideClick);
    window.removeEventListener("scroll", this._reposition, true);
    if (this._dropdown && this._dropdown.parentNode) {
      this._dropdown.parentNode.removeChild(this._dropdown);
    }
  }

  toggle(e) {
    e.stopPropagation();
    if (this._dropdown.classList.contains("hidden")) {
      this._open();
    } else {
      this._close();
    }
  }

  pick(e) {
    const value = e.currentTarget.dataset.value;
    const label = e.currentTarget.dataset.label;
    const select = this.selectTarget;

    select.value = value;
    this._trigger.querySelector("[data-role='label']").textContent = label;

    // Update active state
    this._dropdown.querySelectorAll("[data-role='option']").forEach((opt) => {
      opt.classList.toggle("aurora-select-active", opt.dataset.value === value);
    });

    this._close();
    select.dispatchEvent(new Event("change", { bubbles: true }));
  }

  _open() {
    this._dropdown.classList.remove("hidden");
    this._reposition();
  }

  _close() {
    this._dropdown.classList.add("hidden");
  }

  _reposition = () => {
    if (this._dropdown.classList.contains("hidden")) return;
    const rect = this._trigger.getBoundingClientRect();
    const dh = this._dropdown.offsetHeight;
    const spaceBelow = window.innerHeight - rect.bottom;

    // Horizontal: align right edge of dropdown with right edge of trigger
    const dw = this._dropdown.offsetWidth;
    let left = rect.right - dw;
    if (left < 8) left = rect.left; // fallback: align left if would overflow

    if (spaceBelow < dh + 8 && rect.top > dh + 8) {
      // Open above
      this._dropdown.style.top = `${rect.top - dh - 4}px`;
    } else {
      // Open below
      this._dropdown.style.top = `${rect.bottom + 4}px`;
    }
    this._dropdown.style.left = `${left}px`;
  };

  _handleOutsideClick = (e) => {
    if (!this.element.contains(e.target) && !this._dropdown.contains(e.target)) {
      this._close();
    }
  };

  _buildCustomDropdown() {
    const select = this.selectTarget;
    select.style.display = "none";

    const selectedOption = select.options[select.selectedIndex];
    const selectedLabel = selectedOption ? selectedOption.text : "";

    // Trigger button (stays in DOM where the select was)
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "aurora-select-trigger";
    trigger.addEventListener("click", (e) => this.toggle(e));
    trigger.innerHTML = `
      <span data-role="label">${selectedLabel}</span>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>
    `;
    this._trigger = trigger;
    this.element.appendChild(trigger);

    // Dropdown (appended to body to escape overflow:hidden)
    const dropdown = document.createElement("div");
    dropdown.className = "aurora-select-dropdown hidden";
    dropdown.style.position = "fixed";
    dropdown.style.zIndex = "9999";

    Array.from(select.options).forEach((opt) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "aurora-select-option";
      item.setAttribute("data-role", "option");
      item.dataset.value = opt.value;
      item.dataset.label = opt.text;
      item.textContent = opt.text;
      if (opt.selected) item.classList.add("aurora-select-active");
      item.addEventListener("click", (e) => this.pick(e));
      dropdown.appendChild(item);
    });

    this._dropdown = dropdown;
    document.body.appendChild(dropdown);
  }
}
