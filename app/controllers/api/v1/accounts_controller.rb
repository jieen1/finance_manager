# frozen_string_literal: true

class Api::V1::AccountsController < Api::V1::BaseController
  include Pagy::Backend

  # Ensure proper scope authorization for read access
  before_action :ensure_read_scope

  def index
    family = current_resource_owner.family
    accounts_query = family.accounts.visible.alphabetically

    # Apply filters
    accounts_query = apply_filters(accounts_query)

    # Apply search
    accounts_query = apply_search(accounts_query) if params[:search].present?

    # Handle pagination with Pagy
    @pagy, @accounts = pagy(
      accounts_query,
      page: safe_page_param,
      limit: safe_per_page_param
    )

    @per_page = safe_per_page_param

    # Rails will automatically use app/views/api/v1/accounts/index.json.jbuilder
    render :index
  rescue => e
    Rails.logger.error "AccountsController error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  private

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def apply_filters(query)
      # Classification filtering (asset/liability)
      if params[:classification].present?
        query = query.where(classification: params[:classification])
      end

      # Account type filtering
      if params[:account_type].present?
        query = query.where(accountable_type: params[:account_type].camelize)
      end

      # Multiple account types filtering
      if params[:account_types].present?
        account_types = Array(params[:account_types]).map(&:camelize)
        query = query.where(accountable_type: account_types)
      end

      # Currency filtering
      if params[:currency].present?
        query = query.where(currency: params[:currency])
      end

      # Status filtering
      if params[:status].present?
        query = query.where(status: params[:status])
      end

      query
    end

    def apply_search(query)
      search_term = "%#{params[:search]}%"
      query.where("accounts.name ILIKE ?", search_term)
    end

    def safe_page_param
      page = params[:page].to_i
      page > 0 ? page : 1
    end

    def safe_per_page_param
      per_page = params[:per_page].to_i

      # Default to 25, max 100
      case per_page
      when 1..100
        per_page
      else
        25
      end
    end
end
