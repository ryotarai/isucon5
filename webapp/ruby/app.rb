require 'sinatra/base'
require 'sinatra/contrib'
require 'pg'
require 'tilt/erubis'
require 'erubis'
require 'json' # ojのほうがはやそう
require 'httpclient'
require 'openssl'
require 'redis'
require 'redis/connection/hiredis'
require 'concurrent'
require 'expeditor'

module Isucon5f
  module TimeWithoutZone
    def to_s
      strftime("%F %H:%M:%S")
    end
  end
  ::Time.prepend TimeWithoutZone
end

class Isucon5f::WebApp < Sinatra::Base
  use Rack::Session::Cookie, secret: (ENV['ISUCON5_SESSION_SECRET'] || 'tonymoris')
  set :erb, escape_html: true
  set :public_folder, File.expand_path('../../static', __FILE__)

  SALT_CHARS = [('a'..'z'),('A'..'Z'),('0'..'9')].map(&:to_a).reduce(&:+)

  Endpoint = Struct.new(:token_type, :token_key, :uri)

  ENDPOINTS = {
    'ken2' => Endpoint.new(nil, nil, 'http://api.five-final.isucon.net:8080/'),
    'surname' => Endpoint.new(nil, nil, 'http://api.five-final.isucon.net:8081/surname'),
    'givenname' => Endpoint.new(nil, nil, 'http://api.five-final.isucon.net:8081/givenname'),
    'tenki' => Endpoint.new('param', 'zipcode', 'http://api.five-final.isucon.net:8988/'),
    'perfectsec' => Endpoint.new('header', 'X-PERFECT-SECURITY-TOKEN', 'https://api.five-final.isucon.net:8443/tokens'),
    'perfectsec_attacked' => Endpoint.new('header', 'X-PERFECT-SECURITY-TOKEN', 'https://api.five-final.isucon.net:8443/attacked_list'),
  }

  CLIENT = HTTPClient.new
  CLIENT.ssl_config.verify_mode = OpenSSL::SSL::VERIFY_NONE

  EXPEDITOR_SERVICE = Expeditor::Service.new(
      executor: Concurrent::ThreadPoolExecutor.new(
          min_threads: 5,
          max_threads: 5,
          max_queue: 0,
      )
  )
  # redis is thread-safe
  REDIS_CLIENT = Redis.new(host: 'localhost', port: 6379)

  helpers do
    def config
      @config ||= {
        db: {
          host: ENV['ISUCON5_DB_HOST'] || 'localhost',
          port: ENV['ISUCON5_DB_PORT'] && ENV['ISUCON5_DB_PORT'].to_i,
          username: ENV['ISUCON5_DB_USER'] || 'isucon',
          password: ENV['ISUCON5_DB_PASSWORD'],
          database: ENV['ISUCON5_DB_NAME'] || 'isucon5f',
        },
      }
    end

    def db
      return Thread.current[:isucon5_db] if Thread.current[:isucon5_db]
      conn = PG.connect(
        host: config[:db][:host],
        port: config[:db][:port],
        user: config[:db][:username],
        password: config[:db][:password],
        dbname: config[:db][:database],
        connect_timeout: 3600
      )
      Thread.current[:isucon5_db] = conn
      conn
    end

    def authenticate(email, password)
      query = <<SQL
SELECT id, email, grade FROM users WHERE email=$1 AND passhash=digest(salt || $2, 'sha512')
SQL
      user = nil
      db.exec_params(query, [email, password]) do |result|
        result.each do |tuple|
          user = {id: tuple['id'].to_i, email: tuple['email'], grade: tuple['grade']}
        end
      end
      session[:user_id] = user[:id] if user
      user
    end

    def current_user
      return @user if @user
      return nil unless session[:user_id]
      @user = nil
      db.exec_params('SELECT id,email,grade FROM users WHERE id=$1', [session[:user_id]]) do |r|
        r.each do |tuple|
          @user = {id: tuple['id'].to_i, email: tuple['email'], grade: tuple['grade']}
        end
      end
      session.clear unless @user
      @user
    end

    def generate_salt
      salt = ''
      32.times do
        salt << SALT_CHARS[rand(SALT_CHARS.size)]
      end
      salt
    end

    def put_subscriptions(user_id, arg)
      REDIS_CLIENT.set("subscriptions:#{user_id}", JSON.dump(arg))
    end

    def fetch_subscriptions(user_id)
      json = REDIS_CLIENT.get("subscriptions:#{user_id}")
      JSON.parse(json)
    end
  end

  get '/signup' do
    session.clear
    erb :signup
  end

  post '/signup' do
    email, password, grade = params['email'], params['password'], params['grade']
    salt = generate_salt
    insert_user_query = <<SQL
INSERT INTO users (email,salt,passhash,grade) VALUES ($1,$2,digest($3 || $4, 'sha512'),$5) RETURNING id
SQL
    default_arg = {}
    insert_subscription_query = <<SQL
INSERT INTO subscriptions (user_id,arg) VALUES ($1,$2)
SQL
    db.transaction do |conn|
      user_id = conn.exec_params(insert_user_query, [email,salt,salt,password,grade]).values.first.first
      put_subscriptions(user_id, default_arg)
    end
    redirect '/login'
  end

  post '/cancel' do
    redirect '/signup'
  end

  get '/login' do
    session.clear
    erb :login
  end

  post '/login' do
    authenticate params['email'], params['password']
    halt 403 unless current_user
    redirect '/'
  end

  get '/logout' do
    session.clear
    redirect '/login'
  end

  get '/' do
    unless current_user
      return redirect '/login'
    end
    erb :main, locals: {user: current_user}
  end

  get '/user.js' do
    halt 403 unless current_user
    erb :userjs, content_type: 'application/javascript', locals: {grade: current_user[:grade]}
  end

  get '/modify' do
    user = current_user
    halt 403 unless user
    erb :modify, locals: {user: user}
  end

  post '/modify' do
    user = current_user
    halt 403 unless user

    service = params["service"]
    token = params.has_key?("token") ? params["token"].strip : nil
    keys = params.has_key?("keys") ? params["keys"].strip.split(/\s+/) : nil
    param_name = params.has_key?("param_name") ? params["param_name"].strip : nil
    param_value = params.has_key?("param_value") ? params["param_value"].strip : nil

    arg = fetch_subscriptions(user[:id])
    arg[service] ||= {}
    arg[service]['token'] = token if token
    arg[service]['keys'] = keys if keys
    if param_name && param_value
      arg[service]['params'] ||= {}
      arg[service]['params'][param_name] = param_value
    end
    put_subscriptions(user[:id], arg)

    redirect '/modify'
  end

  def fetch_api(uri, headers, params)
    res = CLIENT.get_content(uri, params, headers)
    JSON.parse(res)
  end

  def cache_json(cache_key)
    data = REDIS_CLIENT.get(cache_key)
    if data
      JSON.parse(data)
    else
      data = yield
      REDIS_CLIENT.set(cache_key, JSON.dump(data))
      data
    end
  end

  def fetch_api_with_cache(service, uri, headers, params)
    case service
    when 'ken2'
      cache_key = "ken2:#{params['zipcode']}"
      cache_json(cache_key) do
        fetch_api(uri, headers, params)
      end
    when 'surname', 'givenname'
      cache_key = "#{service}:#{params['q']}"
      cache_json(cache_key) do
        fetch_api(uri, headers, params)
      end
    else
      fetch_api(uri, headers, params)
    end
  end

  get '/data' do
    unless user = current_user
      halt 403
    end

    arg = fetch_subscriptions(user[:id])

    data = []

    arg.each_pair do |service_orig, conf|
      service =
          if service_orig == 'ken'.freeze
            'ken2'
          else
            service_orig
          end
      endpoint = ENDPOINTS.fetch(service)

      headers = {}
      params = (conf['params'] && conf['params'].dup) || {}
      case endpoint.token_type
        when 'header' then headers[endpoint.token_key] = conf['token']
        when 'param' then params[endpoint.token_key] = conf['token']
      end
      if service_orig == 'ken'.freeze
        params['zipcode'] = conf['keys'][0]
      end
      data << {"service" => service_orig, "data" => fetch_api_with_cache(service, endpoint.uri, headers, params)}
    end
    json data
  end

  get '/initialize' do
    file = File.expand_path("../../sql/initialize.sql", __FILE__)
    system("psql", "-f", file, "isucon5f")

    db.exec_params('SELECT user_id,arg FROM subscriptions').values.each do |user_id, arg|
      put_subscriptions(user_id, JSON.parse(arg))
    end

    'ok'
  end
end
