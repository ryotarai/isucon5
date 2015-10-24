require_relative './app.rb'

if ENV["ENABLE_LINEPROF"]
  require 'rack-lineprof'
  use Rack::Lineprof
end

require 'stackprof'
use StackProf::Middleware, enabled: true,
                           mode: :cpu,
                           interval: 1000,
                           save_every: 5
run Isucon5::WebApp
