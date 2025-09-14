# frozen_string_literal: true

json.id trade.id
json.date trade.entry.date
json.amount trade.entry.amount_money.format
json.currency trade.entry.currency
json.name trade.entry.name
json.notes trade.entry.notes
json.type trade.qty.positive? ? "buy" : "sell"
json.quantity trade.qty.abs
json.price trade.price_money.format(precision: 3)
json.price_currency trade.currency
json.fee trade.fee_money.format(precision: 3)
json.fee_currency trade.fee_currency

# Security information
json.security do
  json.id trade.security.id
  json.ticker trade.security.ticker
  json.name trade.security.name
  json.exchange trade.security.exchange_operating_mic
  json.country_code trade.security.country_code
  json.offline trade.security.offline
end

# Account information
json.account do
  json.id trade.entry.account.id
  json.name trade.entry.account.name
  json.account_type trade.entry.account.accountable_type.underscore
  json.classification trade.entry.account.classification
end

# Additional metadata
json.created_at trade.created_at.iso8601
json.updated_at trade.updated_at.iso8601
