require 'singleton'
require 'vlad_tasks'

class Rake::RemoteTask < Rake::Task
  attr_accessor :options, :target_hosts

  def run command
    raise Vlad::ConfigurationError, "No roles have been defined" if Vlad.instance.roles.empty?

    @target_hosts.each do |host|
      cmd = "ssh #{host} #{command}"
      retval = system cmd
      raise Vlad::CommandFailedError, "execution failed: #{cmd}" unless retval
    end
  end
end

class Vlad
  VERSION = '1.0.0'
  class Error < RuntimeError; end
  class ConfigurationError < Error; end
  class CommandFailedError < Error; end

  include Singleton

  attr_reader :roles, :tasks

  def all_hosts
    @roles.keys.map do |role|
      hosts_for_role(role)
    end.flatten.uniq.sort
  end

  def fetch(name, default = nil)
    name = name.to_s if Symbol === name
    if @env.has_key? name then
      v = @env[name]
      v = @env[name] = v.call if Proc === v
      v
    else
      raise Vlad::ConfigurationError
    end
  end

  def host host_name, *roles
    opts = Hash === roles.last ? roles.pop : {}

    roles.each do |role_name|
      role role_name, host_name, opts.dup
    end
  end

  def hosts_for_role(role)
    @roles[role].keys.sort
  end

  def initialize
    self.reset

    instance_eval File.read("config/deploy.rb") if test ?f, 'config/deploy.rb'
  end

  def method_missing name, *args
    begin
      fetch(name)
    rescue Vlad::ConfigurationError
      super
    end
  end

  def reset
    @roles = Hash.new { |h,k| h[k] = {} }
    @env = {}
    @tasks = {}
    set(:application)       { abort "Please specify the name of the application" }
    set(:repository)        { abort "Please specify the repository type" }
  end

  def role role_name, host, args = {}
    @roles[role_name][host] = args
  end

  def set name, val = nil, &b
    raise ArgumentError, "cannot set reserved name: '#{name}'" if self.respond_to?(name)
    raise ArgumentError, "cannot provide both a value and a block" if b and val
    @env[name.to_s] = val || b
  end

  def task name, options = {}, &b
    roles = options[:roles]
    t = Rake::RemoteTask.define_task(name, &b)
    t.options = options
    t.target_hosts = roles ? hosts_for_role(roles) : all_hosts
    t
  end
end
