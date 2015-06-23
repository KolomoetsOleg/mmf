require "mmf/version"
require 'oauth2'
require 'json'
require 'pp'

class Mmf::Client
  ROOT_URI      = "https://oauth2-api.mapmyapi.com/"

  VAR     = /%\{(.*?)\}/
  API_VERSION = "v7.1"
  API_MAP = {
    # user resources
    me:                 { method: :get,  endpoint: API_VERSION + '/user/self' },
    deactivate:         { method: :post, endpoint: API_VERSION + '/user_deactivation', },
    user:               { method: :get,  endpoint: API_VERSION + '/user/%{user_id}', defaults: { user_id: :me } },
    create_user:        { method: :post, endpoint: API_VERSION + '/user' },
    update_user:        { method: :put,  endpoint: API_VERSION + '/user/%{user_id}', defaults: { user_id: :me } },
    user_photo:         { method: :get,  endpoint: API_VERSION + '/user_profile_photo/%{user_id}', defaults: { user_id: :me } },
    user_stats:         { method: :get,  endpoint: API_VERSION + '/user_stats/%{user_id}', defaults: { user_id: :me } },

    achievement:        { method: :get,  endpoint: API_VERSION + '/acievement/%{achievement_id}' },
    achievements:       { method: :get,  endpoint: API_VERSION + '/user_acievement', required: [:user], defaults: { user: :me } },

    # friend resources
    friends:            { method: :get,    endpoint: API_VERSION + '/user', required: [:friends_with] },
    suggested_friends:  { method: :get,    endpoint: API_VERSION + '/user', required: [:suggested_friends_for, :suggested_friends_source] },
    add_friend:         { method: :post,   endpoint: API_VERSION + '/frendship' },
    remove_friend:      { method: :delete, endpoint: API_VERSION + '/friendship/%{friendship_id}' },
    approve_friend:     { method: :put,    endpoint: API_VERSION + '/friendship/%{friendship_id}' },
    friend_requests:    { method: :get,    endpoint: API_VERSION + '/friendship', required: [:to_user], defaults: { status: 'pending' } },

    # shared resources
    activity_types:     { method: :get,  endpoint: API_VERSION + '/activity_type' },
    activity_type:      { method: :get,  endpoint: API_VERSION + '/activity_type/%{activity_type_id}' },
    privacy_options:    { method: :get,  endpoint: API_VERSION + '/privacy_option' },
    privacy_option:     { method: :get,  endpoint: API_VERSION + '/privacy_option/%{privacy_option_id}' },

    # workout resources
    add_workout:        { method: :post, endpoint: API_VERSION + '/workout', required: [:activity_type, :name, :start_datetime, :start_locale_timezone] },
    workouts:           { method: :get,  endpoint: API_VERSION + '/workout', required: [:user], defaults: { user: :me } },
    workout:            { method: :get,  endpoint: API_VERSION + '/workout/%{workout_id}' },

    # course resources
    search_courses:     { method: :get,  endpoint: API_VERSION + '/course' },
    course:             { method: :get,  endpoint: API_VERSION + '/course/%{course_id}' },
    # course_leaderboard: { method: :get,  endpoint: 'api/0.1/course_leaderboard/%{course_id}', required: [:activity_type_id] },
    # course_history:     { method: :get,  endpoint: '/api/0.1/course_history/%{course_id}_%{user_id}' },
    # course_map:         { method: :get,  endpoint: 'api/0.1/course_map/%{course_id}' },

    # route resources
    route:              { method: :get,    endpoint: API_VERSION + '/route/%{route_id}' },
    routes:             { method: :get,    endpoint: API_VERSION + '/route', required: [:user], defaults: { user: :me } },
    nearby_routes:      { method: :get,    endpoint: API_VERSION + '/route', required: [:close_to_location, :minimum_distance, :maximum_distance] },
    add_route:          { method: :post,   endpoint: API_VERSION + '/route' },
    update_route:       { method: :put,    endpoint: API_VERSION + '/route/%{route_id}' },
    remove_route:       { method: :delete, endpoint: API_VERSION + '/route/%{route_id}' },
    bookmarks:          { method: :get,    endpoint: API_VERSION + '/route_bookmark', required: [:user], defaults: { user: :me } },
    add_bookmark:       { method: :post,   endpoint: API_VERSION + '/route_bookmark/%{route_id}' },
    remove_bookmark:    { method: :delete, endpoint: API_VERSION + '/route_bookmark/%{route_bookmark_id}' }

  }

  attr_accessor :client_key, :client_secret, :access_token

  def initialize
    @client_key, @client_secret, @access_token = '','',''
    yield self
    client  = OAuth2::Client.new(client_key, client_secret)
    @client = OAuth2::AccessToken.new(client, access_token)
  end

  API_MAP.keys.each do |name|
    define_method(name) do |params = {}|
      call(name, params)
    end
  end

  def user_id
    @user_id ||= me['id']
  end

  def api
    API_MAP.any? do |name, details|
      vars = url_params(details[:endpoint])
      context = Hash[vars.zip vars.map {|v| ":#{v}"}]
      endpoint = interpolate(details[:endpoint], context)
      puts "client.#{name}".ljust(30) + "=> [#{details[:method]}]".ljust(12) + endpoint
    end
  end

private

  def call(name, params)
    method, endpoint = API_MAP[name].values_at(:method, :endpoint)
    required = API_MAP[name].fetch(:required, []) + url_params(endpoint).map(&:to_sym)
    defaults = expand_special(name, API_MAP[name].fetch(:defaults, {}))
    params   = defaults.merge(params)
    check_params(name, required, params)
    begin
      request(method, interpolate(endpoint, params), params)
    rescue OAuth2::Error => e
      raise JSON.parse(e.message[1..-1]).pretty_inspect
    end
  end

  def request(method, endpoint, params)
    uri  = "#{ROOT_URI}/#{endpoint}"
    opts = { params: params, headers: {'Api-Key' => client_key} }
    resp = @client.send(method, uri, opts)
    find_relevant_data(JSON.parse(resp.body))
  end

  def find_relevant_data(data)
    case data
    when Hash
      data = data['_embedded'] || data
      data.size == 1 ? data.first[1] : data
    else data
    end
  end

  def interpolate(str, context)
    vars = url_params(str)
    vars.inject(str) do |str, var|
      str.gsub("\%{#{var}}", (context[var.to_sym] || context[var.to_s]).to_s)
    end
  end

  def expand_special(name, params)
    return params if name == :me
    params.inject({}) {|h, (k,v)| h[k] = (v == :me ? user_id : v); h }
  end

  def check_params(name, required, actual)
    return if required.all? { |p| actual[p] }
    raise ArgumentError, "Missing one or more required params #{required} for '#{name}' API call. " +
                         "Check API docs at https://developer.mapmyapi.com/docs for details."
  end

  def url_params(url)
    url.scan(VAR).flatten
  end

end
