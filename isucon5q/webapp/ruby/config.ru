require_relative './app.rb'
require 'rack-lineprof'

use Rack::Lineprof if ENV["ENABLE_LINEPROF"]
use StackProf::Middleware, enabled: true,
                           mode: :cpu,
                           interval: 1000,
                           save_every: 5
run Isucon5::WebApp
