class TasksController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_project
  before_action :set_task, only: [ :show, :edit, :update, :destroy ]

  def index
    @tasks = @project.tasks.includes(:user)
  end

  def show
  end

  def new
    @task = @project.tasks.build
  end

  def create
    @task = @project.tasks.build(task_params)
    if @task.save
      redirect_to project_tasks_path(@project), notice: "Task created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @task.update(task_params)
      if turbo_frame_request_id == "task_status"
        render partial: "tasks/task_status", locals: { task: @task, project: @project }
      elsif turbo_frame_request_id == dom_id(@task)
        render partial: "tasks/task", locals: { task: @task, project: @project }
      else
        redirect_to project_task_path(@project, @task), notice: "Task updated."
      end
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy
    redirect_to project_tasks_path(@project), notice: "Task deleted."
  end

  private

  def set_project
    @project = Project.find(params[:project_id])
  end

  def set_task
    @task = @project.tasks.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:name, :status, :user_id)
  end
end
