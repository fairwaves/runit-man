require 'runit-man/log_location_cache'
require 'runit-man/service_status'

class ServiceInfo
  attr_reader :name

  def initialize(a_name)
    @name   = a_name
    @files  = {}

    @status = ServiceStatus.new(data_from_file(File.join(supervise_folder, 'status')))
    @log_status = ServiceStatus.new(data_from_file(File.join(log_supervise_folder, 'status')))
  end

  def to_json(*a)
    data = {}
    [
      :name, :stat, :active?, :logged?, :switchable?,
      :log_file_location, :log_pid 
    ].each do |sym|
      data[sym] = send(sym)
    end

    [
      :run?, :pid, :finish?, :down?,
      :want_up?, :want_down?, :got_term?,
      :started_at, :uptime
    ].each do |sym|
      data[sym] = @status.send(sym)
    end
    data.to_json(*a)
  end

  def logged?
    File.directory?(log_supervise_folder)
  end

  def stat
    @status.inactive? ? 'inactive' : @status.to_s
  end

  def active?
    File.directory?(active_service_folder) || File.symlink?(active_service_folder)
  end

  def switchable?
    File.symlink?(active_service_folder) || File.directory?(inactive_service_folder)
  end

  def down?
    @status.down?
  end

  def run?
    @status.run?
  end

  def up!
    send_signal :u
  end

  def down!
    send_signal :d
  end

  def switch_down!
    down!
    File.unlink(active_service_folder)
  end

  def switch_up!
    File.symlink(inactive_service_folder, active_service_folder)
  end

  def restart!
    down!
    up!
  end

  def pid
    @status.pid
  end

  def uptime
    @status.uptime
  end

  def log_pid
    @log_status.pid
  end

  def log_file_location
    rel_path = ServiceInfo.log_location_cache[log_pid]
    return nil if rel_path.nil?
    File.expand_path(rel_path, log_run_folder)
  end

  def send_signal(signal)
    return unless supervise?
    File.open(File.join(supervise_folder, 'control'), 'w') do |f|
      f.print signal.to_s
    end
  end

  def files_to_view
    return [] unless File.directory?(files_to_view_folder)
    Dir.entries(files_to_view_folder).select do |name|
      File.symlink?(File.join(files_to_view_folder, name))
    end.map do |name|
      File.expand_path(
        File.readlink(File.join(files_to_view_folder, name)),
        files_to_view_folder
      )
    end.select do |file_path|
      File.file?(file_path)
    end 
  end

  def urls_to_view
    return [] unless File.directory?(urls_to_view_folder)
    Dir.entries(urls_to_view_folder).select do |name|
      name =~ /\.url$/ && File.file?(File.join(urls_to_view_folder, name))
    end.map do |name|
      data_from_file(File.join(urls_to_view_folder, name))
    end.select do |url|
      !url.nil?
    end
  end

  def allowed_signals
    return [] unless File.directory?(allowed_signals_folder)
    Dir.entries(allowed_signals_folder).reject do |name|
      ServiceInfo.itself_or_parent?(name)
    end
  end

private
  def inactive_service_folder
    File.join(RunitMan.all_services_directory, name)
  end

  def active_service_folder
    File.join(RunitMan.active_services_directory, name)
  end

  def files_to_view_folder
    File.join(active_service_folder, 'runit-man', 'files-to-view')
  end

  def urls_to_view_folder
    File.join(active_service_folder, 'runit-man', 'urls-to-view')
  end

  def allowed_signals_folder
    File.join(active_service_folder, 'runit-man', 'allowed-signals')
  end

  def supervise_folder
    File.join(active_service_folder, 'supervise')
  end

  def log_run_folder
    File.join(active_service_folder, 'log')
  end

  def log_supervise_folder
    File.join(log_run_folder, 'supervise')
  end

  def supervise?
    File.directory?(supervise_folder)
  end

  def data_from_file(file_name)
    return @files[file_name] if @files.include?(file_name)
    @files[file_name] = ServiceInfo.real_data_from_file(file_name)
  end

  class << self
    def all
      all_service_names.sort.map do |name|
        ServiceInfo.new(name)
      end
    end

    def [](name)
      all_service_names.include?(name) ? ServiceInfo.new(name) : nil
    end

    def log_location_cache
      unless @log_location_cache
        @log_location_cache = LogLocationCache.new
      end
      @log_location_cache
    end

    def real_data_from_file(file_name)
      return nil unless File.readable?(file_name)
      data = IO.read(file_name)
      data.chomp! unless data.nil?
      data.empty? ? nil : data
    end

    def itself_or_parent?(name)
      name == '.' || name == '..'
    end

  private
    def active_service_names
      return [] unless File.directory?(RunitMan.active_services_directory)
      Dir.entries(RunitMan.active_services_directory).reject do |name|
        full_name = File.join(RunitMan.active_services_directory, name)
        itself_or_parent?(name) || (!File.symlink?(full_name) && !File.directory?(full_name))
      end
    end

    def inactive_service_names
      return [] unless File.directory?(RunitMan.all_services_directory)
      actives = active_service_names
      Dir.entries(RunitMan.all_services_directory).reject do |name|
        full_name = File.join(RunitMan.all_services_directory, name)
        itself_or_parent?(name) || !File.directory?(full_name) || actives.include?(name)
      end
    end

    def all_service_names
      (active_service_names + inactive_service_names)
    end
  end
end

