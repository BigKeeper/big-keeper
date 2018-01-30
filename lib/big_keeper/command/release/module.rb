#!/usr/bin/ruby
require 'big_keeper/util/podfile_operator'
require 'big_keeper/util/gitflow_operator'
require 'big_keeper/dependency/dep_type'
require 'big_keeper/util/info_plist_operator'
require 'big_keeper/util/git_operator'
require 'big_keeper/util/logger'

module BigKeeper
  def self.release_module_start(path, version, user, module_name)
    BigkeeperParser.parse("#{path}/Bigkeeper")

    Dir.chdir(path) do
      git_info = GitInfo.new(BigkeeperParser::home_git, GitType::TAG, version)
      module_path = self.get_module_path_default(path, user, module_name)
      start_module_release(module_path, version, module_name, git_info, user)
    end
  end

  def self.release_module_finish(path, version, user, module_name)
    BigkeeperParser.parse("#{path}/Bigkeeper")
    module_path = self.get_module_path_default(path, user, module_name)

    Logger.error("current branch has changed") unless GitOperator.new.has_changes(module_path)
    # check out master
    if GitOperator.new.current_branch(module_path) != "master"
      current_name = GitOperator.new.current_branch(module_path)
      GitOperator.new.checkout(module_path, "master")
      Logger.highlight("Push branch '#{current_name}' for '#{module_name}'...")
      GitService.new.verify_push(module_path, "finish #{GitflowType.name(GitflowType::RELEASE)} #{current_name}", "master", "#{module_name}")
    end
    return

    Dir.chdir(module_path) do
      # rebase develop to master
      Logger.highlight(%Q(Rebase develop to master))

      #修改 podspec 文件
      # TO DO: - advanced to use Regular Expression
      PodfileOperator.new.podspec_change(%Q(#{module_path}/#{module_name}.podspec), version, module_name)

      GitService.new.verify_rebase(module_path, 'develop', "#{module_name}")
      GitOperator.new.verify_push(module_path, "finish rebase develop to master", "master", "#{module_name}")
      GitOperator.new.tag(module_path, version)

      Logger.highlight(%Q(Start Pod repo push #{module_name}))
      IO.popen("pod repo push #{module_name} #{module_name}.podspec --allow-warnings --sources=#{BigkeeperParser::sourcemodule_path}") do |io|
        io.each do |line|
          has_error = true if line.include? "ERROR"
        end
      end
      if has_error
        Logger.error("Pod repo push in '#{module_name}'")
        return
      end

      Logger.highlight(%Q(Success release #{module_name} V#{version}))
    end
  end

  private
  def self.start_module_release(module_path, version, module_name, source, user)
    if GitOperator.new.has_changes(module_path)
      StashService.new.stash_all(module_path, GitOperator.new.current_branch(module_path), user, module_name.split())
    end

    # step 1 checkout to develop branch
    Logger.highlight(%Q(Start checkout #{module_name} to Branch develop))
    if GitOperator.new.current_branch(module_path) != "develop"
      if GitOperator.new.has_branch(module_path, "develop")
        GitOperator.new.checkout(module_path, "develop")
      else
        Logger.error("Cann't find develop branch, please check.")
      end
    end

    Dir.chdir(module_path) do
      # Pod lib lint
      Logger.highlight(%Q(Start Pod lib lint #{module_name}))
      has_error = false
      IO.popen("pod lib lint --allow-warnings --verbose --use-libraries --sources=#{BigkeeperParser::sourcemodule_path}") do |io|
        io.each do |line|
          has_error = true if line.include? "ERROR"
        end
      end
      if has_error
        Logger.error("Pod lib error in '#{module_name}'")
        return
      end
    end

    GitOperator.new.commit(module_path, "update podspec")
    GitOperator.new.first_push(module_path, GitOperator.new.current_branch(module_path))
    Logger.highlight(%Q(Pod lib lint success))
  end

  def self.get_module_path_default(path, user, module_name)
    module_path = BigkeeperParser::module_path(user, module_name)
    if module_path == "../#{module_name}"
      path_array = path.split('/')
      path_array.pop()
      module_path = path_array.join('/') + "/#{module_name}"
    end
    module_path
  end
end
