class Category < ApplicationRecord
  has_many :transactions, dependent: :nullify, class_name: "Transaction"
  has_many :import_mappings, as: :mappable, dependent: :destroy, class_name: "Import::Mapping"

  belongs_to :family

  has_many :budget_categories, dependent: :destroy
  has_many :subcategories, class_name: "Category", foreign_key: :parent_id, dependent: :nullify
  belongs_to :parent, class_name: "Category", optional: true

  validates :name, :color, :lucide_icon, :family, presence: true
  validates :name, uniqueness: { scope: :family_id }

  validate :category_level_limit
  validate :nested_category_matches_parent_classification

  before_save :inherit_color_from_parent

  scope :alphabetically, -> { order(:name) }
  scope :roots, -> { where(parent_id: nil) }
  scope :incomes, -> { where(classification: "income") }
  scope :expenses, -> { where(classification: "expense") }

  COLORS = %w[#e99537 #4da568 #6471eb #db5a54 #df4e92 #c44fe9 #eb5429 #61c9ea #805dee #6ad28a]

  UNCATEGORIZED_COLOR = "#737373"
  TRANSFER_COLOR = "#444CE7"
  PAYMENT_COLOR = "#db5a54"
  TRADE_COLOR = "#e99537"

  class Group
    attr_reader :category, :subcategories

    delegate :name, :color, to: :category

    def self.for(categories)
      categories.select { |category| category.parent_id.nil? }.map do |category|
        new(category, category.subcategories)
      end
    end

    def initialize(category, subcategories = nil)
      @category = category
      @subcategories = subcategories || []
    end
  end

  class << self
    def icon_codes
      %w[bus circle-dollar-sign ambulance apple award baby battery lightbulb bed-single beer bluetooth book briefcase building credit-card camera utensils cooking-pot cookie dices drama dog drill drum dumbbell gamepad-2 graduation-cap house hand-helping ice-cream-cone phone piggy-bank pill pizza printer puzzle ribbon shopping-cart shield-plus ticket trees]
    end

    def bootstrap!
      default_categories.each do |name, color, icon, classification|
        find_or_create_by!(name: name) do |category|
          category.color = color
          category.classification = classification
          category.lucide_icon = icon
        end
      end
    end

    def uncategorized
      new(
        name: I18n.t("category.label.uncategorized"),
        color: UNCATEGORIZED_COLOR,
        lucide_icon: "circle-dashed"
      )
    end

    private
      def default_categories
        [
          [ I18n.t("category.label.income"), "#e99537", "circle-dollar-sign", "income" ],
          [ I18n.t("category.label.loan_payments"), "#6471eb", "credit-card", "expense" ],
          [ I18n.t("category.label.fees"), "#6471eb", "credit-card", "expense" ],
          [ I18n.t("category.label.entertainment"), "#df4e92", "drama", "expense" ],
          [ I18n.t("category.label.food_drink"), "#eb5429", "utensils", "expense" ],
          [ I18n.t("category.label.shopping"), "#e99537", "shopping-cart", "expense" ],
          [ I18n.t("category.label.home_improvement"), "#6471eb", "house", "expense" ],
          [ I18n.t("category.label.healthcare"), "#4da568", "pill", "expense" ],
          [ I18n.t("category.label.personal_care"), "#4da568", "pill", "expense" ],
          [ I18n.t("category.label.services"), "#4da568", "briefcase", "expense" ],
          [ I18n.t("category.label.gifts_donations"), "#61c9ea", "hand-helping", "expense" ],
          [ I18n.t("category.label.transportation"), "#df4e92", "bus", "expense" ],
          [ I18n.t("category.label.travel"), "#df4e92", "plane", "expense" ],
          [ I18n.t("category.label.rent_utilities"), "#db5a54", "lightbulb", "expense" ]
        ]
      end
  end

  def inherit_color_from_parent
    if subcategory?
      self.color = parent.color
    end
  end

  def replace_and_destroy!(replacement)
    transaction do
      transactions.update_all category_id: replacement&.id
      destroy!
    end
  end

  def parent?
    subcategories.any?
  end

  def subcategory?
    parent.present?
  end

  private
    def category_level_limit
      if (subcategory? && parent.subcategory?) || (parent? && subcategory?)
        errors.add(:parent, "can't have more than 2 levels of subcategories")
      end
    end

    def nested_category_matches_parent_classification
      if subcategory? && parent.classification != classification
        errors.add(:parent, "must have the same classification as its parent")
      end
    end

    def monetizable_currency
      family.currency
    end
end
