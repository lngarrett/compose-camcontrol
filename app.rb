require 'sinatra'
require 'rest-client'
require 'redis' 
require 'yaml'
require 'thin'

set :server, 'thin'
$redis = Redis.new
$config = YAML.load_file('config.yaml')["config"]

Thread.new do
  while true do
    sleep $config["credit"]["interval"]
    incrCredit
  end
end

get '/' do
  $put = $redis.hget("cameras:frontcam", :name) + " " + $redis.hget("cameras:frontcam", :credit) + " " + $count.to_s + " " + $config["credit"]["interval"].to_s
  "#{$put}"
end

get '/:cameraName/motion' do
  alertMotion(params["cameraName"])
end

def pushover(title, message)
  uri = URI.encode("https://api.pushover.net/1/messages.json")
  appKey = $redis.get "config:pushover:app-key"
  userKey = $redis.get "config:pushover:user-key"
  RestClient.post uri, { :token => appKey, :user => userKey, :title => title, :message => message }
end

def seedRedis
  cameras = YAML.load_file('config.yaml')["camera"]
  cameras.each do |camera|
    name = camera['name']
    $redis.hsetnx("cameras:#{name}", :name, camera['name'])
    $redis.hsetnx("cameras:#{name}", :hostname, camera['hostname'])
  end
end

def fullCredit
  cameras = $redis.keys("*cameras*").map { |camera| $redis.hgetall(camera) }
  cameras.each do |camera|
    name = camera["name"]
    $redis.hset("cameras:#{name}", :credit, $config["credit"]["full"])
  end
end

def incrCredit
  cameras = $redis.keys("*cameras*").map { |camera| $redis.hgetall(camera) }
  cameras.each do |camera|
    name = camera["name"]
    credit = camera["credit"]
    $redis.hincrby("cameras:#{name}", :credit, $config["credit"]["increment"]) unless credit.to_i >= $config["credit"]["full"]
  end
end

def decrCredit(cameraName)
  camera = getCamera(cameraName)
  puts "cameras['name']"
  $redis.hincrby("cameras:#{camera['name']}", :credit, -1) unless camera["credit"].to_i == 0
end

# The title string is formatted assuming that cameraName is 
# {location}cam (frontcam, drivewaycam, etc.). Modify the string if yours is different.
def alertMotion(cameraName)
  camera = getCamera(cameraName)
  if camera["credit"].to_i > 0
    title = cameraName.sub("cam", "").capitalize + " Camera"
    message = "Motion Detected"
    pushover(title, message)
    decrCredit(cameraName)
  end
end

def getCamera(cameraName)
  key = "cameras:#{cameraName}"
  $redis.hgetall(key)
end

seedRedis
fullCredit
