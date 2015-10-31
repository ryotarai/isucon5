require 'dotenv'
Dotenv.load

require_relative './app.rb'

if ENV["ENABLE_STACKPROF"]
  require "stackprof"
  use StackProf::Middleware, enabled: true,
                             mode: :wall,
                             interval: 1000,
                             save_every: 5
end

if ENV["ENABLE_LINEPROF"]
  require "rack-lineprof"
  use Rack::Lineprof, profile: "app.rb"
end

run Isucon5f::WebApp
