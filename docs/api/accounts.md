# Accounts API Documentation

The Accounts API allows external applications to retrieve information about financial accounts in Maybe.

## Authentication

All account endpoints require authentication via OAuth2 or API keys with appropriate scopes.

## Endpoints

### List Accounts
```
GET /api/v1/accounts
```

**Required Scope:** `read`

**Query Parameters:**
- `classification` - Filter by classification (`asset` or `liability`)
- `account_type` - Filter by account type (e.g., `investment`, `depository`, `credit_card`)
- `account_types[]` - Filter by multiple account types
- `currency` - Filter by currency code (e.g., `USD`, `CNY`, `EUR`)
- `status` - Filter by account status (`active`, `draft`, `disabled`)
- `search` - Search in account names
- `page` - Page number (default: 1)
- `per_page` - Items per page (default: 25, max: 100)

**Response:**
```json
{
  "accounts": [
    {
      "id": "uuid",
      "name": "Investment Account",
      "balance": "$15,000.00",
      "currency": "USD",
      "classification": "asset",
      "account_type": "investment"
    },
    {
      "id": "uuid",
      "name": "Checking Account",
      "balance": "$2,500.00",
      "currency": "USD",
      "classification": "asset",
      "account_type": "depository"
    },
    {
      "id": "uuid",
      "name": "Credit Card",
      "balance": "$1,200.00",
      "currency": "USD",
      "classification": "liability",
      "account_type": "credit_card"
    }
  ],
  "pagination": {
    "page": 1,
    "per_page": 25,
    "total_count": 15,
    "total_pages": 1
  }
}
```

## Account Types

Maybe supports various types of financial accounts, each with specific characteristics:

### Asset Accounts

#### 1. Depository (存款账户)
- **account_type**: `depository`
- **classification**: `asset`
- **subtypes**:
  - `checking` - 经常账户
  - `savings` - 储蓄账户
  - `wechat` - 微信账户
  - `alipay` - 支付宝账户
- **description**: Traditional bank accounts, digital wallets, and cash equivalents

#### 2. Investment (投资账户)
- **account_type**: `investment`
- **classification**: `asset`
- **subtypes**:
  - `股票` - 股票
  - `基金` - 基金
  - `期货` - 期货
- **description**: Brokerage accounts, investment portfolios, and trading accounts

#### 3. Crypto (加密货币账户)
- **account_type**: `crypto`
- **classification**: `asset`
- **description**: Cryptocurrency wallets and exchange accounts

#### 4. Property (房产账户)
- **account_type**: `property`
- **classification**: `asset`
- **description**: Real estate properties, rental properties, and land

#### 5. Vehicle (车辆账户)
- **account_type**: `vehicle`
- **classification**: `asset`
- **description**: Cars, motorcycles, boats, and other vehicles

#### 6. Other Asset (其他资产)
- **account_type**: `other_asset`
- **classification**: `asset`
- **description**: Jewelry, collectibles, and other valuable assets

### Liability Accounts

#### 7. Credit Card (信用卡)
- **account_type**: `credit_card`
- **classification**: `liability`
- **description**: Credit cards and revolving credit accounts

#### 8. Loan (贷款)
- **account_type**: `loan`
- **classification**: `liability`
- **description**: Mortgages, personal loans, student loans, and other debt

#### 9. Other Liability (其他负债)
- **account_type**: `other_liability`
- **classification**: `liability`
- **description**: Other types of debt and obligations

## Account Properties

### Basic Information
- **id** (string) - Unique identifier for the account
- **name** (string) - Display name of the account
- **balance** (string) - Current balance formatted with currency symbol
- **currency** (string) - Currency code (e.g., "USD", "CNY", "EUR")
- **classification** (string) - Either "asset" or "liability"
- **account_type** (string) - The specific type of account (see Account Types above)

### Account Status
Accounts can have different statuses:
- **active** - Account is active and visible
- **draft** - Account is being set up
- **disabled** - Account is temporarily disabled
- **pending_deletion** - Account is marked for deletion

Only accounts with "active" or "draft" status are returned by the API.

## Usage with Trades API

When creating trades using the Trades API, you need to specify an `account_id`. Here's how to use the Accounts API to get the correct account ID:

### Example: Get Investment Accounts for Trading

```bash
# Get all accounts
curl "https://api.maybefinance.com/api/v1/accounts" \
  -H "X-Api-Key: YOUR_API_KEY"

# Filter for investment accounts only
curl "https://api.maybefinance.com/api/v1/accounts?account_type=investment" \
  -H "X-Api-Key: YOUR_API_KEY"

# Filter for asset accounts only
curl "https://api.maybefinance.com/api/v1/accounts?classification=asset" \
  -H "X-Api-Key: YOUR_API_KEY"

# Search for accounts by name
curl "https://api.maybefinance.com/api/v1/accounts?search=investment" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Example: Create a Trade with Account ID

```bash
# First, get accounts to find the investment account ID
curl "https://api.maybefinance.com/api/v1/accounts" \
  -H "X-Api-Key: YOUR_API_KEY"

# Then use the account ID to create a trade
curl -X POST https://api.maybefinance.com/api/v1/trades \
  -H "X-Api-Key: YOUR_API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
    "account_id": "investment-account-uuid",
    "date": "2024-01-15",
    "type": "buy",
    "ticker": "605117|XSHG",
    "qty": 10,
    "price": 150.00,
    "fee": 9.99
  }'
```

## Error Handling

All endpoints return standard error responses:

```json
{
  "error": "error_code",
  "message": "Human readable error message"
}
```

**Common Error Codes:**
- `unauthorized` - Invalid or missing authentication
- `forbidden` - Insufficient permissions
- `rate_limit_exceeded` - Too many requests

## Rate Limits

Account API endpoints are subject to the standard API rate limits based on your API key tier:
- Standard: 100 requests/hour
- Premium: 1,000 requests/hour
- Enterprise: 10,000 requests/hour

## Examples

### Get All Accounts
```bash
curl "https://api.maybefinance.com/api/v1/accounts" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Accounts with Pagination
```bash
curl "https://api.maybefinance.com/api/v1/accounts?page=2&per_page=50" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Investment Accounts Only
```bash
curl "https://api.maybefinance.com/api/v1/accounts?account_type=investment" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Asset Accounts Only
```bash
curl "https://api.maybefinance.com/api/v1/accounts?classification=asset" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Search Accounts by Name
```bash
curl "https://api.maybefinance.com/api/v1/accounts?search=checking" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Accounts by Currency
```bash
curl "https://api.maybefinance.com/api/v1/accounts?currency=USD" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Multiple Account Types
```bash
curl "https://api.maybefinance.com/api/v1/accounts?account_types[]=investment&account_types[]=depository" \
  -H "X-Api-Key: YOUR_API_KEY"
```

### Get Accounts with OAuth
```bash
curl "https://api.maybefinance.com/api/v1/accounts" \
  -H "Authorization: Bearer YOUR_ACCESS_TOKEN"
```

## Integration Examples

### JavaScript/Node.js
```javascript
// Get all accounts
const response = await fetch('https://api.maybefinance.com/api/v1/accounts', {
  headers: {
    'X-Api-Key': 'YOUR_API_KEY'
  }
});

const data = await response.json();

// Find investment accounts
const investmentAccounts = data.accounts.filter(
  account => account.account_type === 'investment'
);

// Or use the API filter directly
const investmentResponse = await fetch('https://api.maybefinance.com/api/v1/accounts?account_type=investment', {
  headers: {
    'X-Api-Key': 'YOUR_API_KEY'
  }
});
const investmentData = await investmentResponse.json();

// Use the first investment account for trading
if (investmentAccounts.length > 0) {
  const accountId = investmentAccounts[0].id;
  
  // Create a trade
  const tradeResponse = await fetch('https://api.maybefinance.com/api/v1/trades', {
    method: 'POST',
    headers: {
      'X-Api-Key': 'YOUR_API_KEY',
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({
      account_id: accountId,
      date: '2024-01-15',
      type: 'buy',
      ticker: '605117|XSHG',
      qty: 10,
      price: 150.00,
      fee: 9.99
    })
  });
}
```

### Python
```python
import requests

# Get all accounts
response = requests.get(
    'https://api.maybefinance.com/api/v1/accounts',
    headers={'X-Api-Key': 'YOUR_API_KEY'}
)

data = response.json()

# Find investment accounts
investment_accounts = [
    account for account in data['accounts'] 
    if account['account_type'] == 'investment'
]

# Use the first investment account for trading
if investment_accounts:
    account_id = investment_accounts[0]['id']
    
    # Create a trade
    trade_data = {
        'account_id': account_id,
        'date': '2024-01-15',
        'type': 'buy',
        'ticker': '605117|XSHG',
        'qty': 10,
        'price': 150.00,
        'fee': 9.99
    }
    
    trade_response = requests.post(
        'https://api.maybefinance.com/api/v1/trades',
        headers={
            'X-Api-Key': 'YOUR_API_KEY',
            'Content-Type': 'application/json'
        },
        json=trade_data
    )
```

## Notes

- Only accounts with "active" or "draft" status are returned
- Accounts are ordered alphabetically by name
- Balance amounts are formatted with currency symbols
- All amounts are in the account's native currency
- For multi-currency families, you may need to handle currency conversion client-side
