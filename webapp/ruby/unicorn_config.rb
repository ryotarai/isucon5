worker_processes 16
preload_app true
listen 8080
listen "/home/isucon/.unicorn.sock", :backlog => 64
# pid "/home/isucon/webapp/ruby/unicorn.pid"
