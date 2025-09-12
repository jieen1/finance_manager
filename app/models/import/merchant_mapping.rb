class Import::MerchantMapping < Import::Mapping
  class << self
    def mappables_by_key(import)
      unique_values = import.rows.map(&:merchant_name).uniq.compact
      merchants = import.family.merchants.where(name: unique_values).index_by(&:name)
      
      unique_values.index_with { |value| merchants[value] }
    end
  end

  def selectable_values
    family_merchants = import.family.merchants.alphabetically.map { |merchant| [merchant.name, merchant.id] }
    
    unless key.blank?
      family_merchants.unshift ["Add as new merchant", CREATE_NEW_KEY]
    end
    
    family_merchants
  end

  def requires_selection?
    false
  end

  def values_count
    import.rows.select { |row| row.merchant_name == key }.count
  end

  def mappable_class
    FamilyMerchant
  end

  def create_mappable!
    return unless creatable?
    
    self.mappable = import.family.merchants.find_or_create_by!(name: key)
    save!
  end
end
