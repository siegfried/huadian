require 'cgi'
require 'uri'
require 'net/http'
require 'yaml'
require 'openssl'

usage       'publish-site [options]'
aliases     'ps'
summary     'publishing site'
description 'This command publishes site generated to OSS storage.'

flag :h, :help, 'show help for this command' do |value, cmd|
  puts cmd.help
  exit 0
end

option :b, :bucket, 'specify OSS bucket', :argument => :required
option :k, :access_key_id, 'specify OSS Access Key ID', :argument => :required
option :s, :access_key_secret, 'specify OSS Access Key Secret', :argument => :required

secrets           = YAML.load File.read 'secrets.yml'
access_key_id     = secrets['access_key_id']
access_key_secret = secrets['access_key_secret']
bucket            = secrets['bucket']
digest            = OpenSSL::Digest.new('sha1')

def mime_type(path)
  case File.extname(path)
  when '.css'
    'text/css'
  else
    `file --mime #{path}`.match(/\s.+/).to_s[1..-1]
  end
end

run do |opts, args, cmd|
  access_key_id     = opts[:access_key_id] || access_key_id
  access_key_secret = opts[:access_key_secret] || access_key_secret
  bucket            = opts[:bucket] || bucket
  host              = "#{bucket}.oss-cn-hangzhou.aliyuncs.com"

  Dir.chdir 'output' do
    Dir['**/*'].each do |path|
      unless File.directory? path
        date                      = CGI::rfc1123_date(Time.now)
        uri                       = URI::HTTP.build(host: host, path: "/#{path}")
        canonicalized_resource    = "/#{bucket}/#{path}"
        canonicalized_oss_headers = ""
        content_md5               = ''
        content_type              = mime_type(path)
        data                      = "PUT\n#{content_md5}\n#{content_type}\n#{date}\n#{canonicalized_oss_headers}#{canonicalized_resource}"
        signature                 = [OpenSSL::HMAC.digest(digest, access_key_secret, data)].pack("m").strip

        request = Net::HTTP::Put.new(uri)
        file = File.open(path, 'r')
        request.body_stream = file
        request['Content-Type'] = content_type
        request['Content-Length'] = file.size
        request['Date'] = date
        request['Authorization'] = "OSS #{access_key_id}:#{signature}"

        http = Net::HTTP.new(uri.host, uri.port)
        puts "Uploading: #{path}"
        response = http.request request
        case response
        when Net::HTTPSuccess
          puts 'Done!'
        else
          puts 'Failed!'
        end
      end
    end
  end
end
