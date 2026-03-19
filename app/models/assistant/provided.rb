module Assistant::Provided
  extend ActiveSupport::Concern

  def get_model_provider(ai_model)
    # First try family-configured providers (LlmProvider)
    family_provider = find_family_provider(ai_model)
    return family_provider if family_provider

    # Fall back to global registry
    registry.providers.find { |provider| provider.supports_model?(ai_model) }
  end

  private

    def find_family_provider(ai_model)
      return nil unless chat&.user&.family

      family = chat.user.family
      llm_provider = family.llm_providers.enabled.find { |p| p.supports_model?(ai_model) }
      llm_provider&.to_provider
    end

    def registry
      @registry ||= Provider::Registry.for_concept(:llm)
    end
end
