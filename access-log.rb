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
    case @h['req']
      # TODO
    when %r{\AGET /initialize }
      'GET /initialize'
    when %r{\AGET /profile/[^/]+ }
      'GET /profile/:account_name'
    when %r{\AGET /login }
      'GET /login'
    when %r{\AGET /diary/entries/[^/]+ }
      'GET /diary/entries/:account_name'
    when %r{\AGET / }
      'GET /'
    when %r{\APOST /login }
      'POST /login'
    when %r{\AGET /diary/entry/[^/]+ }
      'GET /diary/entry/:entry_id'
    when %r{\APOST /diary/comment/[^/]+ }
      'POST /diary/comment/:entry_id'
    when %r{\AGET /friends }
      'GET /friends'
    when %r{\APOST /friends/[^/]+ }
      'POST /friends/:account_name'
    when %r{\AGET /footprints }
      'GET /footprints'
    when %r{\APOST /diary/entry }
      'POST /diary/entry'
    when %r{\AGET /logout }
      'GET /logout'
    when %r{\APOST /profile/[^/]+ }
      'POST /profile/:account_name'
    when %r{\AGET /css/[^/]+ }
      'GET /css'
    when %r{\AGET /diary/entry/ }
      'GET unknown'
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
