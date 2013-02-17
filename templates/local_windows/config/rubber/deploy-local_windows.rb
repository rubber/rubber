
after "deploy:update_code", "deploy:local_windows:dos2unix_code"

namespace :deploy do

  namespace :local_windows do

    desc <<-DESC
      Runs dos2unix to remove Windows-style line endings after code has been copied
      to remote server
    DESC

    task :dos2unix_code, :except => { :no_release => true } do
      rsudo "find #{release_path} -type f -exec dos2unix -q {} \\;"
    end

  end

end