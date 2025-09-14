# frozen_string_literal: true

class Api::V1::TradesController < Api::V1::BaseController
  include Pagy::Backend

  # Ensure proper scope authorization for read vs write access
  before_action :ensure_read_scope, only: [ :index, :show ]
  before_action :ensure_write_scope, only: [ :create, :update, :destroy ]
  before_action :set_trade, only: [ :show, :update, :destroy ]

  def index
    family = current_resource_owner.family
    trades_query = family.trades.includes(:entry, :security, { entry: :account })

    # Apply filters
    trades_query = apply_filters(trades_query)

    # Apply search
    trades_query = apply_search(trades_query) if params[:search].present?

    # Order by date descending
    trades_query = trades_query.joins(:entry).order("entries.date DESC, trades.created_at DESC")

    # Handle pagination with Pagy
    @pagy, @trades = pagy(
      trades_query,
      page: safe_page_param,
      limit: safe_per_page_param
    )

    # Make per_page available to the template
    @per_page = safe_per_page_param

    # Rails will automatically use app/views/api/v1/trades/index.json.jbuilder
    render :index

  rescue => e
    Rails.logger.error "TradesController#index error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  def show
    # Rails will automatically use app/views/api/v1/trades/show.json.jbuilder
    render :show

  rescue => e
    Rails.logger.error "TradesController#show error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  def create
    family = current_resource_owner.family

    # Validate account_id is present
    unless trade_params[:account_id].present?
      render json: {
        error: "validation_failed",
        message: "Account ID is required",
        errors: [ "Account ID is required" ]
      }, status: :unprocessable_entity
      return
    end

    # Validate required fields for trade creation
    required_fields = %w[date type qty price]
    missing_fields = required_fields.select { |field| trade_params[field].blank? }
    
    if missing_fields.any?
      render json: {
        error: "validation_failed",
        message: "Required fields are missing",
        errors: missing_fields.map { |field| "#{field.humanize} is required" }
      }, status: :unprocessable_entity
      return
    end

    # Validate ticker or manual_ticker is present
    if trade_params[:ticker].blank? && trade_params[:manual_ticker].blank?
      render json: {
        error: "validation_failed",
        message: "Either ticker or manual_ticker is required",
        errors: [ "Ticker symbol is required" ]
      }, status: :unprocessable_entity
      return
    end

    account = family.accounts.find(trade_params[:account_id])
    
    # Use Trade::CreateForm for consistent business logic
    # Remove account_id from params since we pass account object instead
    form_params = trade_params.except(:account_id)
    create_form = Trade::CreateForm.new(form_params.merge(account: account))
    @entry = create_form.create

    if @entry.persisted?
      @trade = @entry.trade
      render :show, status: :created
    else
      render json: {
        error: "validation_failed",
        message: "Trade could not be created",
        errors: @entry.errors.full_messages
      }, status: :unprocessable_entity
    end

  rescue ActiveRecord::RecordNotFound
    render json: {
      error: "not_found",
      message: "Account not found"
    }, status: :not_found
  rescue => e
    Rails.logger.error "TradesController#create error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  def update
    if @entry.update(entry_params_for_update)
      @entry.sync_account_later
      @entry.lock_saved_attributes!
      @trade = @entry.trade
      render :show
    else
      render json: {
        error: "validation_failed",
        message: "Trade could not be updated",
        errors: @entry.errors.full_messages
      }, status: :unprocessable_entity
    end

  rescue => e
    Rails.logger.error "TradesController#update error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  def destroy
    @entry.destroy!
    @entry.sync_account_later

    render json: {
      message: "Trade deleted successfully"
    }, status: :ok

  rescue => e
    Rails.logger.error "TradesController#destroy error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    render json: {
      error: "internal_server_error",
      message: "Error: #{e.message}"
    }, status: :internal_server_error
  end

  private

    def set_trade
      family = current_resource_owner.family
      @trade = family.trades.find(params[:id])
      @entry = @trade.entry
    rescue ActiveRecord::RecordNotFound
      render json: {
        error: "not_found",
        message: "Trade not found"
      }, status: :not_found
    end

    def ensure_read_scope
      authorize_scope!(:read)
    end

    def ensure_write_scope
      authorize_scope!(:write)
    end

    def apply_filters(query)
      # Account filtering
      if params[:account_id].present?
        query = query.joins(:entry).where(entries: { account_id: params[:account_id] })
      end

      if params[:account_ids].present?
        account_ids = Array(params[:account_ids])
        query = query.joins(:entry).where(entries: { account_id: account_ids })
      end

      # Date range filtering
      if params[:start_date].present?
        query = query.joins(:entry).where("entries.date >= ?", Date.parse(params[:start_date]))
      end

      if params[:end_date].present?
        query = query.joins(:entry).where("entries.date <= ?", Date.parse(params[:end_date]))
      end

      # Trade type filtering (buy/sell)
      if params[:type].present?
        case params[:type].downcase
        when "buy"
          query = query.where("trades.qty > 0")
        when "sell"
          query = query.where("trades.qty < 0")
        end
      end

      # Security filtering
      if params[:ticker].present?
        query = query.joins(:security).where("securities.ticker ILIKE ?", "%#{params[:ticker]}%")
      end

      if params[:security_id].present?
        query = query.where(security_id: params[:security_id])
      end

      # Amount filtering
      if params[:min_amount].present?
        min_amount = params[:min_amount].to_f
        query = query.joins(:entry).where("entries.amount >= ?", min_amount)
      end

      if params[:max_amount].present?
        max_amount = params[:max_amount].to_f
        query = query.joins(:entry).where("entries.amount <= ?", max_amount)
      end

      query
    end

    def apply_search(query)
      search_term = "%#{params[:search]}%"

      query.joins(:entry, :security)
           .where(
             "entries.name ILIKE ? OR securities.ticker ILIKE ? OR securities.name ILIKE ?",
             search_term, search_term, search_term
           )
    end

    def trade_params
      # Follow the exact same pattern as TransactionsController
      params.require(:trade).permit(
        :account_id, :date, :amount, :currency, :qty, :price, :fee,
        :ticker, :manual_ticker, :type
      )
    end

    def entry_params_for_update
      entry_params = {
        date: trade_params[:date],
        entryable_attributes: {
          id: @entry.entryable_id,
          qty: calculate_signed_qty,
          price: trade_params[:price],
          fee: trade_params[:fee]
        }.compact_blank
      }

      # Only update amount if provided
      if trade_params[:amount].present?
        entry_params[:amount] = calculate_trade_amount
      end

      entry_params.compact
    end

    def calculate_signed_qty
      return nil unless trade_params[:qty].present?
      
      qty = trade_params[:qty].to_d
      trade_params[:type] == "sell" ? -qty : qty
    end

    def calculate_trade_amount
      return nil unless trade_params[:qty].present? && trade_params[:price].present?
      
      signed_qty = calculate_signed_qty
      fee_amount = (trade_params[:fee] || 0).to_d
      base_amount = signed_qty * trade_params[:price].to_d
      fee_impact = signed_qty.positive? ? fee_amount : -fee_amount
      base_amount + fee_impact
    end

    def safe_page_param
      page = params[:page].to_i
      page > 0 ? page : 1
    end

    def safe_per_page_param
      per_page = params[:per_page].to_i
      case per_page
      when 1..100
        per_page
      else
        25  # Default
      end
    end
end
