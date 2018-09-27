#
#
# http://api.wunderground.com/api/fe94bc0e2730be52/history_YYYYMMDD/q/CA/San_Francisco.json
# http://api.wunderground.com/api/fe94bc0e2730be52/geolookup/conditions/q/pws:KSCMYRTL46.json

# A Free call - format is CSV regardless of 'format' param:
# https://www.wunderground.com/weatherstation/WXDailyHistory.asp?ID=KSCMYRTL46&graphspan=week&month=08&day=23&year=2017&format=1&_ga=2.123483723.13158086.1503528021-1555398973.1503528021


require 'open-uri'
require 'json'
require 'date'
require 'byebug'

module Enumerable

    def sum
      self.inject(0){|accum, i| accum + i }
    end

    def mean
      self.sum/self.length.to_f
    end

    def sample_variance
      m = self.mean
      sum = self.inject(0){|accum, i| accum +(i-m)**2 }
      sum/(self.length - 1).to_f
    end

    def standard_deviation
      return Math.sqrt(self.sample_variance)
    end

end

#API_KEY='fe94bc0e2730be52'

WUDAILY_PATH = 'wudaily.json'

class Pws
    @pws_name
    @pws_info

    def initialize(nm, info)
        @pws_name = nm
        @pws_info = info
    end

    def name
        @pws_name.to_s
    end

    def info
        @pws_info
    end
end

class Stations
    def initialize(stations_h=nil)
        @stations_h = {}    # of Pws
        @stations_a = []    # of Pws.name

        set_stations(stations_h) if(!stations_h.nil?)

        k='WUNDERGROUND_API_KEY'
        if (@api_key=ENV[k]).nil?
            fnm = "./${k}"
            if File.exists?(fnm)
                ak = File.read(fnm)
                @api_key = ak.strip
            else
                throw "WUNDERGROUND_API_KEY not found in environment or file"
            end
        end
    end

    def add_station(nm, info)
        pws = Pws.new(nm, info)
        @stations_h[pws.name.to_sym] = pws
        @stations_a.push(pws.name)
    end

    def set_stations(stations_h)
        stations_h.each do |nm, info|
            add_station(nm, info)
        end
    end

    def sample
        @stations_h[@stations_a.sample]
    end

    def get(nm_or_idx)
      if(!nm_or_idx.nil? && nm_or_idx.match(/^[0-9]+$/).nil?)
        station = @stations_h[nm_or_idx.to_sym]   # a real PWS station name
      else
        nm = nm_or_idx.nil? ? sample : @stations_a[nm_or_idx.to_i]
        @stations_h[nm.to_sym]
      end
    end

    def each(&block)
        @stations_h.each(&block)
    end

    def api_key
        @api_key
    end
end

def obsvDate(od)
    DateTime.new(od['year'], od['mon'], od['mday'], od['hour'], od['min'], od['sec'])
end

# standard deviation for last hour
# 1. Work out the Mean (the simple average of the numbers)
# 2. Then for each number: subtract the Mean and square the result
# 3. Then work out the mean of those squared differences.
# 4. Take the square root of that and we are done!
def getStdDevGust(obsv)
    last_hour = obsv[-1]['date']['hour'].to_i
    last_min = obsv[-1]['date']['min'].to_i
    last_t = last_hour*60 + last_min
    first_t = (last_hour-1)*60 + last_min

    a = []

    obsv.each do |s|
        hour = s['date']['hour'].to_i
        min = s['date']['min'].to_i
        this_t = hour*60 + min
        if(this_t>=first_t)
            a.push(s['wgustm'].to_f)
        end
    end

    return a.standard_deviation
end

def callApi(pws)
  json=nil

  puts "#{pws.name} - #{pws.info}"

  now = Time.new
  today = now.year.to_s + now.month.to_s.rjust(2, '0') + now.day.to_s.rjust(2, '0')

  path = pws.name + '-' + WUDAILY_PATH
  if(File.exists?(path))
	exp = Time.now - (60 * 5) # they have 30min updates
	sbuf = File.stat(path)
	if sbuf.nil? || exp < sbuf.ctime
	  json = JSON.parse(File.read(path))
	  if(!json['history'].nil? && !json['history']['observations'].nil? && json['history']['observations'].length>0)
    	  return json
      end
	end
  end
  
  begin
	puts "Calling API"
	wurl = "http://api.wunderground.com/api/#{@stations.api_key}/history_#{today}/q/pws:#{pws.name}.json"
	open(wurl) do |f|
	  begin
		json = JSON.parse(f.read)
        if(!json['response']['error'].nil?)
          throw json['response']['error']
        end
		File.open(path, 'w') {|fp| fp.write(JSON.pretty_generate(json))}
	  rescue => e
		puts e.to_s
	  end
	end
  rescue => e
    puts e.to_s
  end
  
  return json
end

def getMaxGust(obsv)
  wgustm=0.0
  hr_a=[]
  hr_i=-1
  hr_n=0
  hr=-1
  tm_gust=""
  obsv.each do |s|
    g = s['wgustm'].to_f
	if(g > wgustm)
	  wgustm = g
	  tm_gust = s['date']['pretty']
	end
	if(s['date']['hour'].to_i > hr)
	    hr_a[hr_i] = (hr_a[hr_i] / hr_n).round(2) if(hr_n > 0)
	    hr_n = 0
	    hr = s['date']['hour'].to_i
	    hr_i += 1
	    hr_a[hr_i] = 0.0
	end
	hr_a[hr_i] += g
	hr_n += 1
  end
  hr_a[hr_i] = (hr_a[hr_i] / hr_n).round(2) if(hr_n > 0)
  puts "Wind Gust"
  puts "     Max: #{wgustm}mph at #{tm_gust}"
  s = obsv[-1]
  puts "  Recent: #{s['wgustm'].to_f}mph at #{s['date']['pretty']}"
  puts "  StdDev: #{getStdDevGust(obsv).round(2)}mph (last hour)"
  puts " AvgByHr: #{hr_a.last(5)}mph (last 5 hours to now)"
end

##### MAIN

def print_results(json)
    if !json.nil?
      obsv = json['history']['observations']
      if(obsv.length > 0)
          puts '```'
          puts "Rainfall today: #{json['history']['dailysummary'][0]['precipi']}in"
          getMaxGust(json['history']['observations'])
          getStdDevGust(json['history']['observations'])
          puts '```'
          puts "\n"
      end
    else
      puts "-- No observations found --"
    end
end

@stations = Stations.new({
                 'KSCMYRTL46': '48th Ave. N. and Grissom',
                 'KSCMYRTL73': 'Shipwatch Point, Lake Arrowhead Rd.',
                 'KSCMYRTL24': '26th Ave. S and Hwy 17 bus',
                 'KSCSKIMM4': 'Briarcliffe Acres',
                 'KSCNORTH54': '58th Ave. N, NMB',
                 'KSCNORTH97': 'Cherry Grove',
                 'KNCWILMI67': 'Carolina Beach, NC',
                 'KNCWILMI145': 'Carolina Beach, NC (2)',
               })

if(ARGV[0].nil?)
    @stations.each do |nm, pws|
        json = callApi(pws)
        print_results(json)
    end
else
    json = callApi(@stations.get(ARGV[0]))
    print_results(json)
end
