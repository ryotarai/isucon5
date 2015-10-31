#!/home/isucon/.local/ruby/bin/ruby

class Log
  def initialize(h)
    @h = h
  end

  def response_time
    # unit: ms
    @h['reqtime'].to_f * 1000
  end

  def endpoint
    case [@h['method'], @h['uri']]
    when ['GET', '/initialize']
      'GET /initialize'
    when ['GET', '/']
      'GET /'
    when ['GET', '/login']
      'GET /login'
    when ['POST', '/login']
      'POST /login'
    when ['GET', '/signup']
      'GET /signup'
    when ['POST', '/signup']
      'POST /signup'
    when ['GET', '/user.js']
      'GET /user.js'
    when ['GET', '/data']
      'GET /data'
    when ['GET', '/modify']
      'GET /modify'
    when ['POST', '/modify']
      'POST /modify'
    when ['GET', '/css/bootstrap.min.css'], ['GET', '/css/signin.css'], ['GET', '/css/jumbotron-narrow.css']
      'GET css'
    when ['GET', '/js/jquery-1.11.3.js'], ['GET', '/js/bootstrap.js'], ['GET', '/js/airisu.js']
      'GET js'
    end
  end
end

class Stat < Struct.new(:total_count, :total_time, :average)
end

stats = {}

ARGF.each_line do |line|
  h = {}
  line.chomp.split("\t").each do |seg|
    key, val = seg.split(':', 2)
    if val =~ /\A\d+\z/
      val = val.to_i
    end
    h[key] = val
  end
  next if h.size == 1
  next if h['ua'] != 'Isucon5q bench'

  log = Log.new(h)
  e = log.endpoint
  unless e
    p h
    raise 'Unknown endpoint'
  end
  stats[e] ||= Stat.new(0, 0)
  stats[e].total_count += 1
  stats[e].total_time += log.response_time
end

stats.each do |_, stat|
  stat.average = stat.total_time.to_f / stat.total_count
end
stats.sort_by { |e, stat| -stat.total_time }.each do |e, stat|
  if stat.average >= 0
    meth, path = e.split(' ', 2)
    printf("%5s %-25s total %.2f s (access: %d, average: %.1f ms)\n", meth, path, stat.total_time / 1000.0, stat.total_count, stat.average)
  end
end

# vim: set et sw=2 sts=2 autoindent:
