require 'open-uri'
require 'optparse'
require 'net/https'

options = {queue: []}
optparse = OptionParser.new do |opts|
  opts.on('-q', '--queue QUEUE', 'Queue name') do |q|
    options[:queue].push(q)
  end
  opts.on('-i', '--project_id ID', 'Project id') do |p|
    options[:project_id] = p
  end
  opts.on('-t', '--tests_per_job NTESTS', 'Number of tests per batch') do |t|
    options[:tests_per_job] = t
  end
  opts.on('-a', '--application_url URL', 'URL of the application') do |a|
    options[:application_url] = a
  end
  opts.on('-p', '--application_url_parameters URL', 'Parameters for application') do |p|
    options[:application_url_parameters] = p
  end
  opts.on('-s', '--scheduler URL', 'URL of the scheduler') do |s|
    options[:scheduler] = s
  end
  opts.on('-c', '--cert FILE', 'Location of the SSL certificate') do |c|
    options[:cert] = c
  end
  opts.on('-x', '--cacert FILE', 'Location of the certificate authority file') do |x|
    options[:cacert] = x
  end
  opts.on('-D', '--dry_run', 'No not schedule jobs') do |d|
    options[:dryrun] = true
  end
  opts.on('-v', '--version VERSION', 'Override version number (optional)') do |v|
    options[:version] = v
  end
end

optparse.parse!

[:project_id, :tests_per_job, :application_url, :application_url_parameters].each do |opt|
  unless options.has_key?(opt)
    puts "Missing #{opt.to_s}"
    puts optparse
    exit
  end
end

unless options.has_key?(:scheduler)
  if options.has_key?(:dryrun)
    options[:scheduler] = 'http://dummy-scheduler'
  else
    puts "Missing scheduler so using default one (https://hive-cloud-proxy.core.dev.pod.bbc)"
    options[:scheduler] = "https://hive-cloud-proxy.core.dev.pod.bbc"
    puts optparse
    #exit
  end
end
if options[:queue].length == 0
  puts "Missing queues"
  puts optparse
  exit
end

versions = {}
if options.has_key?(:version)
  versions[options[:version]] = options[:queue]
else
  puts "Missing version"
  puts optparse
  exit
end

puts "============"
puts "Project id: #{options[:project_id]}"
puts "Tests per job: #{options[:tests_per_job]}"
puts "Scheduler: #{options[:scheduler]}"
puts "Application URL: #{options[:application_url]}"
puts "Application URL parameters: #{options[:application_url_parameters]}"
puts "Certificate file: #{options[:cert]}"
puts "CA file: #{options[:cacert]}"
puts "============"

scheduler_url = URI.parse(options[:scheduler] + "/api/batches")
scheduler = Net::HTTP.new(scheduler_url.host, scheduler_url.port)
scheduler.use_ssl = true
scheduler.verify_mode = OpenSSL::SSL::VERIFY_NONE


versions.each do |version, versioned_devices|
  required_devices = versioned_devices & options[:queue]
  next if required_devices.length == 0
  puts "Version: #{version}"
  required_devices.each do |q|
    puts "  #{q}"
  end

  request = Net::HTTP::Post.new(scheduler_url.request_uri)
  request.set_form_data({
                            'version' => version,
                            'project_id' => options[:project_id],
                            'tests_per_job' => options[:tests_per_job],
                            'target_information[application_url]' => options[:application_url],
                            'target_information[application_url_parameters]' => options[:application_url_parameters],
                            'execution_variables[queues]' => required_devices.join(',')
                        })
  if options[:dryrun]
    puts "    (Dry run)"
  else
    response = scheduler.request(request)
    puts "HTTP Response: [#{response.code}] #{response.message}"
    abort("[#{response.code}] #{response.message}") if response.code.to_i < 300
  end
end
