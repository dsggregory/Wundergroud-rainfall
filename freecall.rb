#
# A Free call - format is CSV regardless of 'format' param:
# https://www.wunderground.com/weatherstation/WXDailyHistory.asp?ID=KSCMYRTL46&graphspan=week&month=08&day=23&year=2017&format=1&_ga=2.123483723.13158086.1503528021-1555398973.1503528021

require 'open-uri'
require 'csv'
require 'byebug'

stations = %w(KSCMYRTL46 KSCMYRTL26)

now = Time.new

begin
  # get daily data for this month and look at the last 7 days
  open("https://www.wunderground.com/weatherstation/WXDailyHistory.asp?ID=#{stations[0]}&graphspan=month&month=#{now.month}&day=#{now.day}&year=#{now.year}&format=1") do |f|
	csv = CSV.new(f, {headers: true}).read
	File.open('wufreeweek.csv', 'w') {|fp| fp.write(csv)}
	n=0
	total=0.0
	days = []
	i = csv.length-1
	while(i>=0)
	  # data is a bit wonky so be ready for it
	  if(csv[i]['Date'].nil? || csv[i]['Date']=~/^<br>.*/)
		i = i-1
		next
	  end
	  n = n+1
	  total += csv[i]['PrecipitationSumIn<br>'].to_f
	  days.insert(0, {csv[i]['Date'] => csv[i]['PrecipitationSumIn<br>']})
	  i = i-1
	  break if(n==8)
	end

	puts "Rainfall for the last week:"
	days.each {|d| d.each {|n,v| puts "#{n}: #{v}\""} }
	puts "Total: #{total}\""
  end
rescue => e
  puts e.to_s
end
