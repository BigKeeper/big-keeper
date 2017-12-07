#!/usr/bin/ruby
require 'big_keeper/util/podfile_operator'
require 'big_keeper/util/gitflow_operator'
require 'big_keeper/model/podfile_type'
require 'big_keeper/util/info_plist_operator'
require 'big_keeper/util/log_util'

module BigKeeper
  def self.release_home_start(path, version, user)
    BigkeeperParser.parse("#{path}/Bigkeeper")
    start_release(path, version, BigkeeperParser::module_names, user)
  end

  def self.release_home_finish(path, version)
    Dir.chdir(path) do
      if GitOperator.new.has_branch(path, "release/#{version}")
        if GitOperator.new.current_branch(path) == "release/#{version}"
          GitOperator.new.commit(path, "release: V #{version}")
          GitOperator.new.push(path, "release/#{version}")
          GitflowOperator.new.finish_release(path, version)
          if GitOperator.new.current_branch(path) == "master"
            GitOperator.new.tag(path, version)
          else
            GitOperator.new.git_checkout(path, "master")
            GitOperator.new.tag(path, version)
          end
        else
          raise BigKeeperLog.error("Not in release branch, please check your branches.")
        end
      else
        raise BigKeeperLog.error("Not has release branch, please use release start first.")
      end
    end
  end

  private
  def self.start_release(project_path, version, modules, user)
    Dir.chdir(project_path) do
      # step 0 Stash current branch
      StashService.new.stash(project_path, GitOperator.new.current_branch(project_path), user, modules)

      # step 1 checkout release
      if GitOperator.new.current_branch(project_path) != "release/#{version}"
        if GitOperator.new.has_branch(project_path, "release/#{version}")
          GitOperator.new.git_checkout(project_path, "release/#{version}")
        else
          GitflowOperator.new.start(project_path, version, GitflowType::RELEASE)
          GitOperator.new.push(project_path, "release/#{version}")
        end
      end

      # step 2 replace_modules
      PodfileOperator.new.replace_all_module_release(%Q(#{project_path}/Podfile),
                                                      modules,
                                                      version)

      # step 3 change Info.plist value
      InfoPlistOperator.new.change_version_build(project_path, version)

      p `pod install --project-directory=#{project_path}`
      p `open #{project_path}/*.xcworkspace`
    end
  end
end
