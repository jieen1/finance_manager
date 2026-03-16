import { Controller } from "@hotwired/stimulus";

// Custom dropdown to replace native <select> with styled Aurora dropdown
// Usage: wrap a <select> with data-controller="aurora-select"
// The controller hides the native select and renders a custom dropdown
export default class extends Controller {
  static targets = ["select", "trigger", "dropdown", "options"];

  connect() {
    this._buildCustomDropdown();
    document.addEventListener("click", this._handleOutsideClick);
  }

  disconnect() {
    document.removeEventListener("click", this._handleOutsideClick);
  }

  toggle(e) {
    e.stopPropagation();
    const dropdown = this.dropdownTarget;
    const isOpen = !dropdown.classList.contains("hidden");
    if (isOpen) {
      this._close();
    } else {
      this._open();
    }
  }

  pick(e) {
    const value = e.currentTarget.dataset.value;
    const label = e.currentTarget.dataset.label;
    const select = this.selectTarget;

    select.value = value;
    this.triggerTarget.querySelector("[data-role='label']").textContent = label;

    // Update active state
    this.optionsTarget.querySelectorAll("[data-role='option']").forEach((opt) => {
      opt.classList.toggle("aurora-select-active", opt.dataset.value === value);
    });

    this._close();

    // Dispatch change event on native select to trigger auto-submit etc
    select.dispatchEvent(new Event("change", { bubbles: true }));
  }

  _open() {
    this.dropdownTarget.classList.remove("hidden");
    // Position dropdown
    const rect = this.triggerTarget.getBoundingClientRect();
    const dropdown = this.dropdownTarget;
    const spaceBelow = window.innerHeight - rect.bottom;
    if (spaceBelow < 200 && rect.top > 200) {
      dropdown.style.bottom = "100%";
      dropdown.style.top = "auto";
      dropdown.style.marginBottom = "4px";
      dropdown.style.marginTop = "0";
    } else {
      dropdown.style.top = "100%";
      dropdown.style.bottom = "auto";
      dropdown.style.marginTop = "4px";
      dropdown.style.marginBottom = "0";
    }
  }

  _close() {
    this.dropdownTarget.classList.add("hidden");
  }

  _handleOutsideClick = (e) => {
    if (!this.element.contains(e.target)) {
      this._close();
    }
  };

  _buildCustomDropdown() {
    const select = this.selectTarget;
    select.style.display = "none";

    const selectedOption = select.options[select.selectedIndex];
    const selectedLabel = selectedOption ? selectedOption.text : "";

    // Build trigger button
    const trigger = document.createElement("button");
    trigger.type = "button";
    trigger.className = "aurora-select-trigger";
    trigger.setAttribute("data-aurora-select-target", "trigger");
    trigger.setAttribute("data-action", "aurora-select#toggle");
    trigger.innerHTML = `
      <span data-role="label">${selectedLabel}</span>
      <svg width="12" height="12" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 9l6 6 6-6"/></svg>
    `;

    // Build dropdown
    const dropdown = document.createElement("div");
    dropdown.className = "aurora-select-dropdown hidden";
    dropdown.setAttribute("data-aurora-select-target", "dropdown");

    const optionsContainer = document.createElement("div");
    optionsContainer.className = "aurora-select-options";
    optionsContainer.setAttribute("data-aurora-select-target", "options");

    Array.from(select.options).forEach((opt) => {
      const item = document.createElement("button");
      item.type = "button";
      item.className = "aurora-select-option";
      item.setAttribute("data-role", "option");
      item.setAttribute("data-value", opt.value);
      item.setAttribute("data-label", opt.text);
      item.setAttribute("data-action", "aurora-select#pick");
      item.textContent = opt.text;
      if (opt.selected) {
        item.classList.add("aurora-select-active");
      }
      optionsContainer.appendChild(item);
    });

    dropdown.appendChild(optionsContainer);
    this.element.appendChild(trigger);
    this.element.appendChild(dropdown);
  }
}
