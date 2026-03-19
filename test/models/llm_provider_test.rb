require "test_helper"

class LlmProviderTest < ActiveSupport::TestCase
  setup do
    @provider = llm_providers(:deepseek)
  end

  test "valid provider" do
    assert @provider.valid?
  end

  test "requires name" do
    @provider.name = nil
    assert_not @provider.valid?
  end

  test "requires api_endpoint" do
    @provider.api_endpoint = nil
    assert_not @provider.valid?
  end

  test "requires valid role" do
    @provider.role = "invalid"
    assert_not @provider.valid?
  end

  test "name must be unique per family" do
    duplicate = @provider.dup
    assert_not duplicate.valid?
  end

  test "enabled scope" do
    family = families(:dylan_family)
    enabled = family.llm_providers.enabled
    assert enabled.all?(&:enabled?)
  end

  test "by_role scope" do
    family = families(:dylan_family)
    main_providers = family.llm_providers.by_role("main")
    assert main_providers.all? { |p| p.role == "main" }
  end

  test "resolved_models returns model names" do
    assert_includes @provider.resolved_models, "deepseek-chat"
  end

  test "supports_model checks resolved models" do
    assert @provider.supports_model?("deepseek-chat")
    assert_not @provider.supports_model?("gpt-4")
  end

  test "primary_model returns first model" do
    assert_equal "deepseek-chat", @provider.primary_model
  end

  test "to_provider returns GenericOpenai instance" do
    provider_instance = @provider.to_provider
    assert_instance_of Provider::GenericOpenai, provider_instance
  end

  test "encrypts api_key" do
    @provider.update!(api_key: "secret-key-123")
    @provider.reload
    assert_equal "secret-key-123", @provider.api_key
  end
end
