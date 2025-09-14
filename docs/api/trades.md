# Trades API Documentation

The Trades API allows external applications to manage investment trades (buy/sell transactions) in Maybe.

## Authentication

All trade endpoints require authentication via OAuth2 or API keys with appropriate scopes.

## Endpoints

### List Trades
```
GET /api/v1/trades
```

**Required Scope:** `read`

**Query Parameters:**
- `account_id` - Filter by account ID
- `account_ids[]` - Filter by multiple account IDs
- `start_date` - Filter trades from this date (YYYY-MM-DD)
- `end_date` - Filter trades to this date (YYYY-MM-DD)
- `type` - Filter by trade type (`buy` or `sell`)
- `ticker` - Filter by security ticker (partial match)
- `security_id` - Filter by security ID
- `min_amount` - Filter by minimum trade amount
- `max_amount` - Filter by maximum trade amount
- `search` - Search in trade name, security ticker, or security name
- `page` - Page number (default: 1)
- `per_page` - Items per page (default: 25, max: 100)

**Response:**
```json
{
  "trades": [
    {
      "id": "uuid",
      "date": "2024-01-15",
      "amount": "$1,509.99",
      "currency": "USD",
      "name": "Buy 10 shares of AAPL",
      "notes": null,
      "type": "buy",
      "quantity": 10,
      "price": "$150.00",
      "fee": "$9.99",
      "security": {
        "id": "uuid",
        "ticker": "AAPL",
        "name": "Apple Inc.",
        "exchange": "XNAS",
        "country_code": "US",
        "offline": false
      },
      "account": {
        "id": "uuid",
        "name": "Investment Account",
        "account_type": "investment",
        "classification": "asset"
      },
      "created_at": "2024-01-15T10:30:00Z",
      "updated_at": "2024-01-15T10:30:00Z"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total_count": 100,
    "total_pages": 4
  }
}
```

### Get Trade
```
GET /api/v1/trades/:id
```

**Required Scope:** `read`

**Response:**
```json
{
  "id": "uuid",
  "date": "2024-01-15",
  "amount": "$1,509.99",
  "currency": "USD",
  "name": "Buy 10 shares of AAPL",
  "notes": null,
  "type": "buy",
  "quantity": 10,
  "price": "$150.00",
  "fee": "$9.99",
  "security": {
    "id": "uuid",
    "ticker": "AAPL",
    "name": "Apple Inc.",
    "exchange": "XNAS",
    "country_code": "US",
    "offline": false
  },
  "account": {
    "id": "uuid",
    "name": "Investment Account",
    "account_type": "investment",
    "classification": "asset"
  },
  "created_at": "2024-01-15T10:30:00Z",
  "updated_at": "2024-01-15T10:30:00Z"
}
```

### Create Trade
```
POST /api/v1/trades
```

**Required Scope:** `write`

**Request Body:**
```json
{
  "account_id": "uuid",
  "date": "2024-01-15",
  "type": "buy",
  "ticker": "605117|XSHG",
  "qty": 10,
  "price": 150.00,
  "fee": 9.99,
  "currency": "USD"
}
```

**Field Descriptions:**
- `account_id` (required) - ID of the account to create the trade in
- `date` (required) - Trade date (YYYY-MM-DD)
- `type` (required) - Trade type: `buy` or `sell`
- `ticker` (optional) - Security ticker with exchange (format: "TICKER|EXCHANGE")
- `manual_ticker` (optional) - Manual ticker symbol (alternative to ticker)
- `qty` (required) - Quantity of shares/units
- `price` (required) - Price per share/unit
- `fee` (optional) - Trading fee (default: 0)
- `currency` (optional) - Currency code (defaults to family currency)

**Note:** Either `ticker` or `manual_ticker` must be provided.

**Response:** Same as Get Trade endpoint (status: 201 Created)

### Update Trade
```
PATCH /api/v1/trades/:id
```

**Required Scope:** `write`

**Request Body:**
```json
{
  "date": "2024-01-16",
  "qty": 15,
  "price": 155.00,
  "fee": 12.99
}
```

**Field Descriptions:**
- `date` (optional) - New trade date
- `qty` (optional) - New quantity
- `price` (optional) - New price per share
- `fee` (optional) - New trading fee

**Response:** Same as Get Trade endpoint

### Delete Trade
```
DELETE /api/v1/trades/:id
```

**Required Scope:** `write`

**Response:**
```json
{
  "message": "Trade deleted successfully"
}
```

## Trade Types

### Buy Trade
- `type`: "buy"
- `qty`: Positive number
- `amount`: Negative (money flowing out of account)

### Sell Trade
- `type`: "sell"  
- `qty`: Positive number (will be stored as negative)
- `amount`: Positive (money flowing into account)

## Security Resolution

The API supports two methods for specifying securities:

### 1. Provider Ticker (Recommended)
```
"ticker": "605117|XSHG"
```
- Format: "TICKER|EXCHANGE"
- Automatically resolves security details
- Supports real-time price updates

### 2. Manual Ticker
```
"manual_ticker": "600941.SH"
```
- Simple ticker symbol
- Creates an "offline" security
- No automatic price updates
- Useful for private securities or when provider is unavailable

## Amount Calculation

Trade amounts are calculated as:
```
amount = (qty * price) + fee_impact
```

Where:
- For buy trades: `fee_impact = +fee` (fee increases cost)
- For sell trades: `fee_impact = -fee` (fee reduces proceeds)

## Error Handling

All endpoints return standard error responses:

```json
{
  "error": "error_code",
  "message": "Human readable error message",
  "errors": ["Detailed validation errors"] // optional
}
```

**Common Error Codes:**
- `unauthorized` - Invalid or missing authentication
- `forbidden` - Insufficient permissions
- `not_found` - Trade or account not found
- `validation_failed` - Invalid request data
- `rate_limit_exceeded` - Too many requests

**Validation Errors:**
- Missing required fields (account_id, date, type, qty, price)
- Invalid trade type (must be "buy" or "sell")
- Missing ticker information (ticker or manual_ticker required)
- Invalid date format
- Negative quantities or prices

## Rate Limits

Trade API endpoints are subject to the standard API rate limits based on your API key tier:
- Standard: 100 requests/hour
- Premium: 1,000 requests/hour
- Enterprise: 10,000 requests/hour

## Examples

### Create a Buy Trade
```bash
curl -X POST https://api.maybefinance.com/api/v1/trades \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "account_id": "account-uuid",
    "date": "2024-01-15",
    "type": "buy",
    "ticker": "605117|XSHG",
    "qty": 10,
    "price": 150.00,
    "fee": 9.99
  }'
```

### Create a Sell Trade
```bash
curl -X POST https://api.maybefinance.com/api/v1/trades \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "account_id": "account-uuid",
    "date": "2024-01-15",
    "type": "sell",
    "manual_ticker": "0700.HK",
    "qty": 5,
    "price": 2500.00,
    "fee": 4.95
  }'
```

### List Trades with Filters
```bash
curl "https://api.maybefinance.com/api/v1/trades?account_id=account-uuid&type=buy&start_date=2024-01-01&per_page=50" \
  -H "X-Api-Key: YOUR_API_KEY" \
```

### Update Trade
```bash
curl -X PATCH https://api.maybefinance.com/api/v1/trades/trade-uuid \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "qty": 15,
    "price": 155.00
  }'
```

### Delete Trade
```bash
curl -X DELETE https://api.maybefinance.com/api/v1/trades/trade-uuid \
  -H "X-Api-Key: YOUR_API_KEY" \
```
