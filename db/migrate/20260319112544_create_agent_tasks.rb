class CreateAgentTasks < ActiveRecord::Migration[7.2]
  def change
    create_table :agent_tasks, id: :uuid do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid

      # 基本信息
      t.string :name, null: false
      t.text :description
      t.string :task_type, null: false, default: "cron"

      # 调度配置
      t.string :schedule_type, null: false, default: "every"
      t.string :cron_expression
      t.integer :interval_minutes
      t.datetime :run_at
      t.string :timezone, default: "Asia/Shanghai"

      # 执行配置
      t.string :action_type, null: false
      t.jsonb :action_params, default: {}
      t.string :model_override
      t.integer :timeout_seconds, default: 120

      # 状态
      t.string :status, null: false, default: "active"
      t.datetime :last_run_at
      t.datetime :next_run_at
      t.integer :run_count, default: 0
      t.integer :fail_count, default: 0
      t.text :last_error
      t.jsonb :last_result, default: {}

      t.timestamps
    end

    add_index :agent_tasks, [:family_id, :status]
    add_index :agent_tasks, [:next_run_at, :status]
  end
end
