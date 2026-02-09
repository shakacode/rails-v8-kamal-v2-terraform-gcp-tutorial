module ApplicationHelper
  def deploy_timestamp
    return unless DeployInfo.build_time

    "deployed #{time_ago_in_words(DeployInfo.build_time)} ago"
  end
end
