# frozen_string_literal: true

module DeployInfo
  GIT_REVISION = ENV.fetch("GIT_REVISION", nil)
  GIT_REVISION_SHORT = GIT_REVISION&.slice(0, 7)
  BUILD_TIME = begin
    Time.parse(ENV.fetch("BUILD_TIME", ""))
  rescue ArgumentError
    nil
  end

  def self.git_revision
    GIT_REVISION
  end

  def self.git_revision_short
    GIT_REVISION_SHORT
  end

  def self.build_time
    BUILD_TIME
  end

  def self.available?
    GIT_REVISION.present?
  end
end
