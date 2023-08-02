require "set"
require "JSON"
require_relative "./ops"
require_relative "./cert"
require_relative "./flatten"

def _drop_unused_files(new, old)
  (old - new)
    .select { |path| File.file?(path) }
    .each do |path|
      File.delete(path)
      p "deleted #{path}"
    end
end

def _drop_unused_dirs(new, old)
  (old - new)
    .select { |path| File.directory?(path) }
    .sort { |a, b| b.split("/").length <=> a.split("/").length }
    .each do |path|
      next if Dir.children(path).length != 0
      Dir.rmdir(path)
      p "deleted #{path}"
    end
end

def config_init(env)
  cfg = env[:cfg]
  tpl = env[:tpl]
  abort("config already exist") if File.exist?(cfg)
  content = File.read("#{tpl}/config/#{cfg}")
  File.write("#{cfg}", content)
end

def config_sync(env)
  cfg = env[:cfg]
  pki = env[:pki]
  tpl = env[:tpl]
  out = env[:out]
  abort("config not exist") unless File.exist?(cfg)

  config = JSON.load_file(cfg)
  servers = [config["server"]]
  clients = config["clients"]

  v_cert_names = cert_names(env)
  server_names = servers.map { |s| s["name"] }
  client_names = clients.map { |c| c["name"] }

  for cert_name in v_cert_names - (server_names + client_names)
    cert_revoke(env, cert_name)
  end

  for server_name in server_names - v_cert_names
    cert_create_server(env, server_name)
  end

  for client_name in client_names - v_cert_names
    cert_create_client(env, client_name)
  end

  var_servers = servers.map { |server| flatten(server, :server) }
  var_clients = clients.map { |client| flatten(client, :client) }
  ops_new = [
    *var_servers
      .map { |var_server| ops_server(env, var_server, var_clients) }
      .flatten,
    *var_clients
      .map { |var_client| ops_client(env, var_servers.first, var_client) }
      .flatten
  ]
  dst_new = ops_new.map { |op| op[:dst] }
  dst_old = Dir.glob("#{out}/**/*")

  for op in ops_new
    src = op[:src]
    dst = op[:dst]
    var = op[:var]
    mod = op[:mod]

    src_content = File.read(src)
    dst_content = src_content % var

    unless File.exist?(dst)
      dir = File.dirname(dst)
      FileUtils.mkdir_p(dir)
      File.write(dst, dst_content)
      p "created #{dst}"
    end

    unless File.read(dst) == dst_content
      File.write(dst, dst_content)
      p "updated #{dst}"
    end

    unless mod.nil? or File.stat(dst).mode & 0777 == mod
      FileUtils.chmod(mod, dst)
      p "updated #{dst}"
      next
    end
  end

  _drop_unused_files(dst_new, dst_old)
  _drop_unused_dirs(dst_new, dst_old)
end
