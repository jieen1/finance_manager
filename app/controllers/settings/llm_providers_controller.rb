class Settings::LlmProvidersController < ApplicationController
  before_action :set_provider, only: %i[edit update destroy]

  def index
    @breadcrumbs = [ [ "首页", root_path ], [ "模型配置", nil ] ]
    @llm_providers = Current.family.llm_providers.alphabetically
    render layout: "settings"
  end

  def new
    @llm_provider = LlmProvider.new(family: Current.family, role: "main")
  end

  def create
    @llm_provider = LlmProvider.new(build_params.merge(family: Current.family))

    if @llm_provider.save
      respond_to do |format|
        format.html { redirect_to settings_llm_providers_path, notice: "模型提供商已创建" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, settings_llm_providers_path) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @llm_provider.update(build_params)
      respond_to do |format|
        format.html { redirect_to settings_llm_providers_path, notice: "模型提供商已更新" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, settings_llm_providers_path) }
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @llm_provider.destroy!
    redirect_to settings_llm_providers_path, notice: "模型提供商已删除"
  end

  private

    def set_provider
      @llm_provider = Current.family.llm_providers.find(params[:id])
    end

    def build_params
      permitted = params.require(:llm_provider).permit(:name, :api_endpoint, :api_key, :role, :priority, :enabled, :models)
      attrs = permitted.to_h

      # Parse comma-separated model names into a hash
      if attrs["models"].is_a?(String)
        model_names = attrs["models"].split(",").map(&:strip).reject(&:blank?)
        attrs["models"] = model_names.each_with_index.to_h { |name, i| [ "model_#{i}", name ] }
      end

      attrs
    end
end
