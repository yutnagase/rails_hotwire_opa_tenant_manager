class TasksController < ApplicationController
  before_action :set_project
  before_action :set_task, only: [ :show, :update ]

  def index
    @tasks = @project.tasks.includes(:user)
  end

  def show
  end

  def update
    if @task.update(task_params)
      if turbo_frame_request_id == "task_status"
        render partial: "tasks/task_status", locals: { task: @task, project: @project }
      else
        render partial: "tasks/task", locals: { task: @task, project: @project }
      end
    else
      render :show, status: :unprocessable_entity
    end
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_task
    @task = @project.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:status)
  end
end
