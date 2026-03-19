require "test_helper"

class Assistant::Function::MemorySearchTest < ActiveSupport::TestCase
  setup do
    @user = users(:family_admin)
    @function = Assistant::Function::MemorySearch.new(@user)
  end

  test "searches all memories by default" do
    result = @function.call("query" => "投资")
    assert result[:count] > 0
    assert result[:results].any? { |r| r[:value].include?("投资") }
  end

  test "searches core memories only" do
    result = @function.call("query" => "投资", "memory_type" => "core")
    assert result[:results].all? { |r| r[:type] == "core" }
  end

  test "searches archival memories only" do
    result = @function.call("query" => "消费分析", "memory_type" => "archival")
    assert result[:results].all? { |r| r[:type] == "archival" }
  end

  test "returns empty for no matches" do
    result = @function.call("query" => "xyz_nonexistent_query")
    assert_equal 0, result[:count]
  end
end
