require "test_helper"

class Assistant::Function::CreateTransactionTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @function = Assistant::Function::CreateTransaction.new(@user)
    @account = accounts(:depository)
  end

  test "creates a transaction entry" do
    assert_difference [ "Entry.count", "Transaction.count" ], 1 do
      result = @function.call(
        "account_name" => @account.name,
        "date" => "2026-03-19",
        "amount" => 35.5,
        "description" => "午餐外卖",
        "category_name" => "餐饮"
      )

      assert result[:success]
      assert result[:entry_id].present?
      assert_equal "餐饮", result[:category]
    end
  end

  test "creates transaction without category" do
    assert_difference "Entry.count", 1 do
      result = @function.call(
        "account_name" => @account.name,
        "date" => "2026-03-19",
        "amount" => -1000,
        "description" => "工资"
      )

      assert result[:success]
    end
  end

  test "raises for unknown account" do
    assert_raises ActiveRecord::RecordNotFound do
      @function.call(
        "account_name" => "NonexistentAccount",
        "date" => "2026-03-19",
        "amount" => 10,
        "description" => "test"
      )
    end
  end

  test "tool_name is create_transaction" do
    assert_equal "create_transaction", Assistant::Function::CreateTransaction.tool_name
  end
end
