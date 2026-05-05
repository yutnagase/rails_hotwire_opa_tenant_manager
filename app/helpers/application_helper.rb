module ApplicationHelper
  def can?(action, resource)
    OpaClient.allowed?(user: current_user, action: action, resource: resource)
  end

  def status_badge_class(status)
    case status
    when "todo"  then "bg-gray-100 text-gray-700"
    when "doing" then "bg-yellow-100 text-yellow-800"
    when "done"  then "bg-green-100 text-green-700"
    else "bg-gray-100 text-gray-700"
    end
  end
end
