import { Controller } from "@hotwired/stimulus";

export default class extends Controller {
  static targets = ["leftSidebar", "rightSidebar", "mobileSidebar", "nav"];
  static classes = [
    "expandedSidebar",
    "collapsedSidebar",
  ];

  openMobileSidebar() {
    this.mobileSidebarTarget.classList.remove("hidden");
  }

  closeMobileSidebar() {
    this.mobileSidebarTarget.classList.add("hidden");
  }

  toggleNav() {
    if (this.hasNavTarget) {
      this.navTarget.classList.toggle("expanded");
    }
  }

  toggleLeftSidebar() {
    const isOpen = this.leftSidebarTarget.classList.contains("w-full");
    this.#updateUserPreference("show_sidebar", !isOpen);
    this.#toggleSidebarWidth(this.leftSidebarTarget, isOpen);
  }

  toggleRightSidebar() {
    const isOpen = this.rightSidebarTarget.classList.contains("w-full");
    this.#updateUserPreference("show_ai_sidebar", !isOpen);
    this.#toggleSidebarWidth(this.rightSidebarTarget, isOpen);
  }

  #toggleSidebarWidth(el, isCurrentlyOpen) {
    if (isCurrentlyOpen) {
      el.classList.remove(...this.expandedSidebarClasses);
      el.classList.add(...this.collapsedSidebarClasses);
    } else {
      el.classList.add(...this.expandedSidebarClasses);
      el.classList.remove(...this.collapsedSidebarClasses);
    }
  }

  #updateUserPreference(field, value) {
    fetch(`/users/${this.userIdValue}`, {
      method: "PATCH",
      headers: {
        "Content-Type": "application/x-www-form-urlencoded",
        "X-CSRF-Token": document.querySelector('[name="csrf-token"]').content,
        Accept: "application/json",
      },
      body: new URLSearchParams({
        [`user[${field}]`]: value,
      }).toString(),
    });
  }
}
