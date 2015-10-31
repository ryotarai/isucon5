require 'sinatra/base'
require 'sinatra/contrib'
require 'pg'
require 'tilt/erubis'
require 'erubis'
require 'oj'
require 'httpclient'
require 'openssl'
require 'redis'
require 'redis/connection/hiredis'
require 'concurrent'
require 'expeditor'
require 'time'

class Tenki

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

  REDIS_CLIENT = Redis.new(
      host: ENV['REDIS_HOST'] || 'localhost',
      port: (ENV['REDIS_PORT'] || 6379).to_i,
  )

  EXPEDITOR_SERVICE = Expeditor::Service.new(
      executor: Concurrent::ThreadPoolExecutor.new(
          min_threads: 10,
          max_threads: 10,
          max_queue: 0,
      )
  )

  def run
    endpoint = ENDPOINTS['tenki']

    commands = []

    REDIS_CLIENT.keys("tenki:*").each do |key|
      command = Expeditor::Command.new(service: EXPEDITOR_SERVICE) do
        begin
          zipcode = key.split(':')[1]
          puts "update zipcode=#{zipcode}"
          content = CLIENT.get_content(endpoint.uri, {zipcode: zipcode})
          REDIS_CLIENT.set(key, content)
        rescue => e
          STDERR.put(e)
        end
        nil
      end

      command.start
      commands << command
    end

    commands.each(&:get)
  end
end

loop do
  Tenki.new.run
end

