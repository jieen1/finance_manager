class AgentTasksController < ApplicationController
  before_action :set_task, only: %i[edit update destroy execute]

  def index
    @breadcrumbs = [ [ "首页", root_path ], [ "任务中心", nil ] ]
    @tasks = Current.family.agent_tasks.recent
    @active_count = Current.family.agent_tasks.active.count
    render layout: "settings"
  end

  def new
    @agent_task = AgentTask.new(family: Current.family, schedule_type: "every", action_type: "custom", interval_minutes: 60)
  end

  def create
    @agent_task = AgentTask.new(task_params.merge(family: Current.family, task_type: "user"))

    if @agent_task.save
      respond_to do |format|
        format.html { redirect_to agent_tasks_path, notice: "任务已创建" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, agent_tasks_path) }
      end
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    @agent_task = @task
  end

  def update
    # 暂停/恢复操作
    case params[:action_type]
    when "pause"
      @task.pause!
      return redirect_to agent_tasks_path
    when "resume"
      @task.resume!
      return redirect_to agent_tasks_path
    end

    # 正常编辑更新
    if @task.update(task_params)
      respond_to do |format|
        format.html { redirect_to agent_tasks_path, notice: "任务已更新" }
        format.turbo_stream { render turbo_stream: turbo_stream.action(:redirect, agent_tasks_path) }
      end
    else
      @agent_task = @task
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    if @task.system?
      redirect_to agent_tasks_path, alert: "系统任务不允许删除"
    else
      @task.destroy!
      redirect_to agent_tasks_path, notice: "任务已删除"
    end
  end

  def execute
    @task.execute!(Current.user)
    redirect_to agent_tasks_path, notice: "任务 \"#{@task.name}\" 已手动执行"
  end

  private

    def set_task
      @task = Current.family.agent_tasks.find(params[:id])
    end

    def task_params
      params.require(:agent_task).permit(
        :name, :description, :action_type, :schedule_type,
        :interval_minutes, :cron_expression, :run_at, :model_override, :timeout_seconds
      )
    end
end
