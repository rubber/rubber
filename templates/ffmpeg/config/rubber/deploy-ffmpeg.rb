namespace :rubber do
  namespace :ffmpeg do

    rubber.allow_optional_tasks(self)

    # Use Jon Severinsson's FFmpeg PPA so we can install the "real" ffmpeg (Ubuntu uses libav / avconv)
    before "rubber:install_packages", "rubber:ffmpeg:setup_apt_sources"
    task :setup_apt_sources do
      run "add-apt-repository -y ppa:jon-severinsson/ffmpeg"
    end
  end
end

