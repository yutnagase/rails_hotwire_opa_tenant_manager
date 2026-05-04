module ApplicationHelper
  def can?(action, resource)
    OpaClient.allowed?(user: current_user, action: action, resource: resource)
  end
end
