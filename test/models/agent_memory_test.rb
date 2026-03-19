require "test_helper"

class AgentMemoryTest < ActiveSupport::TestCase
  setup do
    @memory = agent_memories(:risk_profile)
    @family = families(:dylan_family)
  end

  test "valid memory" do
    assert @memory.valid?
  end

  test "requires value" do
    @memory.value = nil
    assert_not @memory.valid?
  end

  test "requires valid memory_type" do
    @memory.memory_type = "invalid"
    assert_not @memory.valid?
  end

  test "core memory requires key" do
    memory = AgentMemory.new(family: @family, memory_type: "core", value: "test")
    assert_not memory.valid?
  end

  test "archival memory does not require key" do
    memory = AgentMemory.new(family: @family, memory_type: "archival", value: "test", key: "some_key")
    assert memory.valid?
  end

  test "core scope" do
    core = @family.agent_memories.core
    assert core.all?(&:core?)
  end

  test "archival scope" do
    archival = @family.agent_memories.archival
    assert archival.all?(&:archival?)
  end

  test "search finds matching memories" do
    results = @family.agent_memories.search("投资")
    assert results.any?
    assert results.all? { |m| m.value.include?("投资") }
  end

  test "search returns empty for non-matching" do
    results = @family.agent_memories.search("xyz_nonexistent")
    assert results.empty?
  end

  test "core key uniqueness per family" do
    duplicate = AgentMemory.new(family: @family, memory_type: "core", key: "risk_profile", value: "duplicate")
    assert_not duplicate.valid?
  end
end
