# frozen_string_literal: true

module DeployInfo
  GIT_REVISION = ENV.fetch("GIT_REVISION", nil)
  BUILD_TIME = ENV.fetch("BUILD_TIME", nil)

  def self.git_revision
    GIT_REVISION
  end

  def self.git_revision_short
    GIT_REVISION&.first(7)
  end

  def self.build_time
    return unless BUILD_TIME

    Time.parse(BUILD_TIME)
  rescue ArgumentError
    nil
  end

  def self.available?
    GIT_REVISION.present?
  end
end
