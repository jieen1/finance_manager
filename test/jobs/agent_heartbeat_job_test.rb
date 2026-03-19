require "test_helper"

class AgentHeartbeatJobTest < ActiveJob::TestCase
  test "processes families with heartbeat enabled" do
    family = families(:dylan_family)
    family.update!(agent_heartbeat_enabled: true, agent_heartbeat_checklist: ["检查预算执行", "检查异常消费"])

    assert_difference "AgentAction.count", 2 do
      AgentHeartbeatJob.perform_now
    end

    actions = AgentAction.where(source: "heartbeat").last(2)
    assert actions.all? { |a| a.tool_name == "heartbeat_check" }
    assert actions.all? { |a| a.status == "executed" }
  end

  test "skips families with heartbeat disabled" do
    families(:dylan_family).update!(agent_heartbeat_enabled: false)

    assert_no_difference "AgentAction.count" do
      AgentHeartbeatJob.perform_now
    end
  end

  test "skips families with empty checklist" do
    families(:dylan_family).update!(agent_heartbeat_enabled: true, agent_heartbeat_checklist: [])

    assert_no_difference "AgentAction.count" do
      AgentHeartbeatJob.perform_now
    end
  end
end
