require_relative './app.rb'
require "stackprof"

use StackProf::Middleware, enabled: true,
                           mode: :wall,
                           interval: 1000,
                           save_every: 5

if ENV["ENABLE_LINEPROF"]
  require "rack-lineprof"
  use Rack::Lineprof, profile: "app.rb"
end

run Isucon5f::WebApp
