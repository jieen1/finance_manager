require "test_helper"

class Settings::LlmProvidersControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @provider = llm_providers(:deepseek)
  end

  test "index" do
    get settings_llm_providers_path
    assert_response :ok
  end

  test "new" do
    get new_settings_llm_provider_path
    assert_response :ok
  end

  test "create" do
    assert_difference "LlmProvider.count", 1 do
      post settings_llm_providers_path, params: {
        llm_provider: {
          name: "Qwen",
          api_endpoint: "https://dashscope.aliyuncs.com/compatible-mode/v1",
          api_key: "sk-test",
          role: "fast",
          priority: 1
        }
      }
    end
    assert_redirected_to settings_llm_providers_path
  end

  test "create with invalid params" do
    assert_no_difference "LlmProvider.count" do
      post settings_llm_providers_path, params: {
        llm_provider: { name: "", api_endpoint: "" }
      }
    end
    assert_response :unprocessable_entity
  end

  test "edit" do
    get edit_settings_llm_provider_path(@provider)
    assert_response :ok
  end

  test "update" do
    patch settings_llm_provider_path(@provider), params: {
      llm_provider: { name: "DeepSeek V2" }
    }
    assert_redirected_to settings_llm_providers_path
    assert_equal "DeepSeek V2", @provider.reload.name
  end

  test "destroy" do
    assert_difference "LlmProvider.count", -1 do
      delete settings_llm_provider_path(@provider)
    end
    assert_redirected_to settings_llm_providers_path
  end
end
